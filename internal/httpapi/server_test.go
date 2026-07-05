package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"toki/internal/httpapi"
	"toki/internal/store"
)

func TestInviteOnlyMagicLinkSessionAndMe(t *testing.T) {
	srv := newTestServer(t, "alice@example.com")

	if res := postJSON(t, srv, "/v1/auth/magic-link", map[string]any{"email": "not-invited@example.com"}, ""); res.Code != http.StatusForbidden {
		t.Fatalf("non-invited email status = %d, want %d", res.Code, http.StatusForbidden)
	}

	magic := decodeResponse[struct {
		Token string `json:"token"`
	}](t, postJSON(t, srv, "/v1/auth/magic-link", map[string]any{"email": "ALICE@example.com"}, ""))
	if magic.Token == "" {
		t.Fatal("magic link token is empty")
	}

	session := decodeResponse[struct {
		Token string `json:"sessionToken"`
		User  struct {
			Email       string `json:"email"`
			DisplayName string `json:"displayName"`
		} `json:"user"`
		Memberships []any `json:"teamMemberships"`
	}](t, postJSON(t, srv, "/v1/auth/session", map[string]any{"token": magic.Token, "deviceName": "Alice Mac"}, ""))
	if session.Token == "" {
		t.Fatal("session token is empty")
	}
	if session.User.Email != "alice@example.com" {
		t.Fatalf("session user email = %q, want alice@example.com", session.User.Email)
	}
	if session.User.DisplayName != "alice" {
		t.Fatalf("session display name = %q, want alice", session.User.DisplayName)
	}
	if len(session.Memberships) != 1 {
		t.Fatalf("session memberships len = %d, want 1", len(session.Memberships))
	}

	me := decodeResponse[struct {
		User struct {
			Email string `json:"email"`
		} `json:"user"`
		Memberships []any `json:"teamMemberships"`
		Devices     []any `json:"devices"`
	}](t, get(t, srv, "/v1/me", session.Token))
	if me.User.Email != "alice@example.com" {
		t.Fatalf("me email = %q, want alice@example.com", me.User.Email)
	}
	if len(me.Memberships) != 1 {
		t.Fatalf("memberships len = %d, want 1", len(me.Memberships))
	}
	if len(me.Devices) != 1 {
		t.Fatalf("devices len = %d, want 1", len(me.Devices))
	}
}

func TestConversationMembershipRules(t *testing.T) {
	srv := newTestServer(t, "alice@example.com", "bob@example.com", "carol@example.com")
	alice := signIn(t, srv, "alice@example.com")
	bob := signIn(t, srv, "bob@example.com")
	carol := signIn(t, srv, "carol@example.com")

	direct := decodeResponse[createConversationResponse](t, postJSON(t, srv, "/v1/conversations", map[string]any{
		"type":      "direct",
		"memberIds": []string{bob.UserID},
	}, alice.Token)).Conversation
	duplicate := decodeResponse[createConversationResponse](t, postJSON(t, srv, "/v1/conversations", map[string]any{
		"type":      "direct",
		"memberIds": []string{bob.UserID},
	}, alice.Token)).Conversation
	if duplicate.ID != direct.ID {
		t.Fatalf("duplicate direct id = %q, want %q", duplicate.ID, direct.ID)
	}

	aliceList := decodeResponse[struct {
		Conversations []conversationResponse `json:"conversations"`
	}](t, get(t, srv, "/v1/conversations", alice.Token))
	bobList := decodeResponse[struct {
		Conversations []conversationResponse `json:"conversations"`
	}](t, get(t, srv, "/v1/conversations", bob.Token))
	carolList := decodeResponse[struct {
		Conversations []conversationResponse `json:"conversations"`
	}](t, get(t, srv, "/v1/conversations", carol.Token))

	if len(aliceList.Conversations) != 1 || aliceList.Conversations[0].ID != direct.ID {
		t.Fatalf("alice conversations = %+v, want direct only", aliceList.Conversations)
	}
	if len(bobList.Conversations) != 1 || bobList.Conversations[0].ID != direct.ID {
		t.Fatalf("bob conversations = %+v, want direct only", bobList.Conversations)
	}
	if len(carolList.Conversations) != 0 {
		t.Fatalf("carol conversations len = %d, want 0", len(carolList.Conversations))
	}

	group := decodeResponse[createConversationResponse](t, postJSON(t, srv, "/v1/conversations", map[string]any{
		"type":        "group",
		"displayName": "Launch",
		"memberIds":   []string{bob.UserID},
	}, alice.Token)).Conversation
	if res := postJSON(t, srv, "/v1/conversations/"+group.ID+"/members", map[string]any{"memberIds": []string{"user_missing"}}, alice.Token); res.Code != http.StatusBadRequest {
		t.Fatalf("adding non-team user status = %d, want %d", res.Code, http.StatusBadRequest)
	}
}

func TestGroupConversationMaximumTenParticipants(t *testing.T) {
	emails := []string{
		"alice@example.com",
		"member1@example.com", "member2@example.com", "member3@example.com",
		"member4@example.com", "member5@example.com", "member6@example.com",
		"member7@example.com", "member8@example.com", "member9@example.com",
		"member10@example.com",
	}
	srv := newTestServer(t, emails...)
	alice := signIn(t, srv, "alice@example.com")
	var memberIDs []string
	for _, email := range emails[1:] {
		memberIDs = append(memberIDs, signIn(t, srv, email).UserID)
	}

	if res := postJSON(t, srv, "/v1/conversations", map[string]any{
		"type":        "group",
		"displayName": "Too Large",
		"memberIds":   memberIDs,
	}, alice.Token); res.Code != http.StatusBadRequest {
		t.Fatalf("oversized group status = %d, want %d", res.Code, http.StatusBadRequest)
	}

	group := decodeResponse[createConversationResponse](t, postJSON(t, srv, "/v1/conversations", map[string]any{
		"type":        "group",
		"displayName": "Beta Team",
		"memberIds":   memberIDs[:9],
	}, alice.Token)).Conversation
	if len(group.Members) != 10 {
		t.Fatalf("group member count = %d, want 10", len(group.Members))
	}

	if res := postJSON(t, srv, "/v1/conversations/"+group.ID+"/members", map[string]any{"memberIds": []string{memberIDs[9]}}, alice.Token); res.Code != http.StatusBadRequest {
		t.Fatalf("adding eleventh group member status = %d, want %d", res.Code, http.StatusBadRequest)
	}
}

func newTestServer(t *testing.T, invitedEmails ...string) http.Handler {
	t.Helper()

	st := store.NewMemoryStore()
	if _, err := st.SeedDevelopmentTeam(context.Background(), "Toki Beta", invitedEmails); err != nil {
		t.Fatalf("seed development team: %v", err)
	}
	return httpapi.NewServer(st)
}

type signedInUser struct {
	Token    string
	UserID   string
	DeviceID string
}

func signIn(t *testing.T, srv http.Handler, email string) signedInUser {
	t.Helper()

	magic := decodeResponse[struct {
		Token string `json:"token"`
	}](t, postJSON(t, srv, "/v1/auth/magic-link", map[string]any{"email": email}, ""))
	session := decodeResponse[struct {
		Token string `json:"sessionToken"`
		User  struct {
			ID string `json:"id"`
		} `json:"user"`
		Device struct {
			ID string `json:"id"`
		} `json:"device"`
	}](t, postJSON(t, srv, "/v1/auth/session", map[string]any{"token": magic.Token, "deviceName": email + " Mac"}, ""))

	return signedInUser{Token: session.Token, UserID: session.User.ID, DeviceID: session.Device.ID}
}

type conversationResponse struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Members []struct {
		User struct {
			ID string `json:"id"`
		} `json:"user"`
	} `json:"members"`
	LastPresence struct {
		OnlineUserIDs []string `json:"onlineUserIds"`
	} `json:"lastPresence"`
}

type createConversationResponse struct {
	Conversation conversationResponse `json:"conversation"`
}

func postJSON(t *testing.T, srv http.Handler, path string, body map[string]any, token string) *httptest.ResponseRecorder {
	t.Helper()

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res := httptest.NewRecorder()
	srv.ServeHTTP(res, req)
	return res
}

func get(t *testing.T, srv http.Handler, path string, token string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res := httptest.NewRecorder()
	srv.ServeHTTP(res, req)
	return res
}

func decodeResponse[T any](t *testing.T, res *httptest.ResponseRecorder) T {
	t.Helper()

	if res.Code < 200 || res.Code > 299 {
		t.Fatalf("status = %d, body = %s", res.Code, res.Body.String())
	}
	var out T
	if err := json.Unmarshal(res.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode response: %v; body=%s", err, res.Body.String())
	}
	return out
}
