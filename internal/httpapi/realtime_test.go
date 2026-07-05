package httpapi_test

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestRealtimeWebSocketRequiresSessionToken(t *testing.T) {
	srv := httptest.NewServer(newTestServer(t, "alice@example.com"))
	defer srv.Close()

	req, err := http.NewRequest(http.MethodGet, srv.URL+"/v1/realtime", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Sec-WebSocket-Key", websocketKey(t))
	req.Header.Set("Sec-WebSocket-Version", "13")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("realtime request: %v", err)
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", res.StatusCode, http.StatusUnauthorized)
	}
}

func TestRealtimeJoinBroadcastsPresenceAndCleansUpOnClose(t *testing.T) {
	srv := httptest.NewServer(newTestServer(t, "alice@example.com", "bob@example.com"))
	defer srv.Close()

	alice := signIn(t, srv.Config.Handler, "alice@example.com")
	bob := signIn(t, srv.Config.Handler, "bob@example.com")
	conversation := decodeResponse[createConversationResponse](t, postJSON(t, srv.Config.Handler, "/v1/conversations", map[string]any{
		"type":      "direct",
		"memberIds": []string{bob.UserID},
	}, alice.Token)).Conversation

	aliceWS := dialWebSocket(t, srv.URL, "/v1/realtime", alice.Token)
	defer aliceWS.Close()
	bobWS := dialWebSocket(t, srv.URL, "/v1/realtime", bob.Token)

	aliceWS.WriteJSON(t, map[string]any{
		"type":           "room.join",
		"id":             "alice-join",
		"conversationId": conversation.ID,
		"sentAt":         time.Now().UTC().Format(time.RFC3339Nano),
		"payload":        map[string]any{"active": true},
	})
	aliceSnapshot := aliceWS.ReadJSON(t)
	if aliceSnapshot["type"] != "room.snapshot" {
		t.Fatalf("alice first event type = %v, want room.snapshot", aliceSnapshot["type"])
	}

	bobWS.WriteJSON(t, map[string]any{
		"type":           "room.join",
		"id":             "bob-join",
		"conversationId": conversation.ID,
		"sentAt":         time.Now().UTC().Format(time.RFC3339Nano),
		"payload":        map[string]any{"active": true},
	})
	bobSnapshot := bobWS.ReadJSON(t)
	if bobSnapshot["type"] != "room.snapshot" {
		t.Fatalf("bob first event type = %v, want room.snapshot", bobSnapshot["type"])
	}
	presence := aliceWS.ReadJSON(t)
	if presence["type"] != "presence.updated" {
		t.Fatalf("alice presence event type = %v, want presence.updated", presence["type"])
	}
	payload := presence["payload"].(map[string]any)
	if payload["deviceId"] != bob.DeviceID || payload["status"] != "joined" {
		t.Fatalf("presence payload = %+v, want bob joined", payload)
	}

	bobWS.Close()
	presence = aliceWS.ReadJSON(t)
	payload = presence["payload"].(map[string]any)
	if presence["type"] != "presence.updated" || payload["deviceId"] != bob.DeviceID || payload["status"] != "left" {
		t.Fatalf("cleanup presence = %+v payload=%+v, want bob left", presence, payload)
	}
}

func TestRealtimeSignalingIsForwardedOnlyInsideJoinedRoom(t *testing.T) {
	srv := httptest.NewServer(newTestServer(t, "alice@example.com", "bob@example.com", "carol@example.com"))
	defer srv.Close()

	alice := signIn(t, srv.Config.Handler, "alice@example.com")
	bob := signIn(t, srv.Config.Handler, "bob@example.com")
	carol := signIn(t, srv.Config.Handler, "carol@example.com")
	authorized := decodeResponse[createConversationResponse](t, postJSON(t, srv.Config.Handler, "/v1/conversations", map[string]any{
		"type":      "direct",
		"memberIds": []string{bob.UserID},
	}, alice.Token)).Conversation
	other := decodeResponse[createConversationResponse](t, postJSON(t, srv.Config.Handler, "/v1/conversations", map[string]any{
		"type":      "direct",
		"memberIds": []string{carol.UserID},
	}, alice.Token)).Conversation

	aliceWS := dialWebSocket(t, srv.URL, "/v1/realtime", alice.Token)
	defer aliceWS.Close()
	bobWS := dialWebSocket(t, srv.URL, "/v1/realtime", bob.Token)
	defer bobWS.Close()

	joinRoom(t, aliceWS, authorized.ID, "alice-join")
	joinRoom(t, bobWS, authorized.ID, "bob-join")
	_ = aliceWS.ReadJSON(t)

	aliceWS.WriteJSON(t, map[string]any{
		"type":           "signal.offer",
		"id":             "offer-1",
		"conversationId": authorized.ID,
		"sentAt":         time.Now().UTC().Format(time.RFC3339Nano),
		"payload": map[string]any{
			"targetDeviceId": bob.DeviceID,
			"sdp":            "fake-offer-sdp",
		},
	})
	forwarded := bobWS.ReadJSON(t)
	if forwarded["type"] != "signal.forwarded" {
		t.Fatalf("bob event type = %v, want signal.forwarded", forwarded["type"])
	}
	payload := forwarded["payload"].(map[string]any)
	if payload["senderDeviceId"] != alice.DeviceID || payload["targetDeviceId"] != bob.DeviceID {
		t.Fatalf("forwarded payload = %+v, want alice -> bob devices", payload)
	}

	aliceWS.WriteJSON(t, map[string]any{
		"type":           "signal.answer",
		"id":             "answer-1",
		"conversationId": other.ID,
		"sentAt":         time.Now().UTC().Format(time.RFC3339Nano),
		"payload": map[string]any{
			"targetDeviceId": carol.DeviceID,
			"sdp":            "fake-answer-sdp",
		},
	})
	errorEvent := aliceWS.ReadJSON(t)
	if errorEvent["type"] != "error" {
		t.Fatalf("cross-room event type = %v, want error", errorEvent["type"])
	}
}

func joinRoom(t *testing.T, ws *testWebSocket, conversationID string, eventID string) {
	t.Helper()

	ws.WriteJSON(t, map[string]any{
		"type":           "room.join",
		"id":             eventID,
		"conversationId": conversationID,
		"sentAt":         time.Now().UTC().Format(time.RFC3339Nano),
		"payload":        map[string]any{"active": true},
	})
	if event := ws.ReadJSON(t); event["type"] != "room.snapshot" {
		t.Fatalf("join event type = %v, want room.snapshot", event["type"])
	}
}

type testWebSocket struct {
	conn net.Conn
	r    *bufio.Reader
}

func dialWebSocket(t *testing.T, serverURL string, path string, token string) *testWebSocket {
	t.Helper()

	u, err := url.Parse(serverURL)
	if err != nil {
		t.Fatalf("parse server url: %v", err)
	}
	key := websocketKey(t)
	conn, err := net.Dial("tcp", u.Host)
	if err != nil {
		t.Fatalf("dial websocket: %v", err)
	}
	req := fmt.Sprintf("GET %s HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer %s\r\n\r\n", path, u.Host, key, token)
	if _, err := io.WriteString(conn, req); err != nil {
		t.Fatalf("write handshake: %v", err)
	}
	reader := bufio.NewReader(conn)
	status, err := reader.ReadString('\n')
	if err != nil {
		t.Fatalf("read handshake status: %v", err)
	}
	if !strings.Contains(status, "101") {
		t.Fatalf("handshake status = %q, want 101", strings.TrimSpace(status))
	}
	headers := make(http.Header)
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("read handshake header: %v", err)
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		name, value, ok := strings.Cut(line, ":")
		if ok {
			headers.Add(name, strings.TrimSpace(value))
		}
	}
	if got, want := headers.Get("Sec-WebSocket-Accept"), websocketAccept(key); got != want {
		t.Fatalf("websocket accept = %q, want %q", got, want)
	}
	return &testWebSocket{conn: conn, r: reader}
}

func (ws *testWebSocket) WriteJSON(t *testing.T, v any) {
	t.Helper()

	payload, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal websocket payload: %v", err)
	}
	if err := writeClientTextFrame(ws.conn, payload); err != nil {
		t.Fatalf("write websocket frame: %v", err)
	}
}

func (ws *testWebSocket) ReadJSON(t *testing.T) map[string]any {
	t.Helper()

	payload, err := readServerTextFrame(ws.r)
	if err != nil {
		t.Fatalf("read websocket frame: %v", err)
	}
	var out map[string]any
	if err := json.Unmarshal(payload, &out); err != nil {
		t.Fatalf("decode websocket event: %v; payload=%s", err, payload)
	}
	return out
}

func (ws *testWebSocket) Close() {
	_ = ws.conn.Close()
}

func websocketKey(t *testing.T) string {
	t.Helper()

	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		t.Fatalf("websocket key: %v", err)
	}
	return base64.StdEncoding.EncodeToString(b[:])
}

func websocketAccept(key string) string {
	h := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	return base64.StdEncoding.EncodeToString(h[:])
}

func writeClientTextFrame(w io.Writer, payload []byte) error {
	header := []byte{0x81}
	switch {
	case len(payload) < 126:
		header = append(header, byte(0x80|len(payload)))
	case len(payload) <= 0xffff:
		header = append(header, 0x80|126, byte(len(payload)>>8), byte(len(payload)))
	default:
		header = append(header, 0x80|127)
		var size [8]byte
		binary.BigEndian.PutUint64(size[:], uint64(len(payload)))
		header = append(header, size[:]...)
	}
	var mask [4]byte
	if _, err := rand.Read(mask[:]); err != nil {
		return err
	}
	header = append(header, mask[:]...)
	masked := append([]byte(nil), payload...)
	for i := range masked {
		masked[i] ^= mask[i%4]
	}
	if _, err := w.Write(header); err != nil {
		return err
	}
	_, err := w.Write(masked)
	return err
}

func readServerTextFrame(r *bufio.Reader) ([]byte, error) {
	for {
		first, err := r.ReadByte()
		if err != nil {
			return nil, err
		}
		second, err := r.ReadByte()
		if err != nil {
			return nil, err
		}
		opcode := first & 0x0f
		length := int(second & 0x7f)
		switch length {
		case 126:
			var size [2]byte
			if _, err := io.ReadFull(r, size[:]); err != nil {
				return nil, err
			}
			length = int(binary.BigEndian.Uint16(size[:]))
		case 127:
			var size [8]byte
			if _, err := io.ReadFull(r, size[:]); err != nil {
				return nil, err
			}
			length64 := binary.BigEndian.Uint64(size[:])
			if length64 > 1<<20 {
				return nil, fmt.Errorf("frame too large: %d", length64)
			}
			length = int(length64)
		}
		payload := make([]byte, length)
		if _, err := io.ReadFull(r, payload); err != nil {
			return nil, err
		}
		if opcode == 0x1 {
			return payload, nil
		}
	}
}
