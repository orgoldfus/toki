package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"toki/internal/auth"
	"toki/internal/store"
)

type Logger interface {
	Printf(format string, v ...any)
}

type Hub struct {
	store  store.Store
	logger Logger

	mu    sync.Mutex
	rooms map[string]*room
}

type room struct {
	clients map[string]*client
}

type client struct {
	connectionID   string
	userID         string
	deviceID       string
	active         bool
	conversationID string
	ws             *webSocketConn
}

func NewHub(st store.Store, logger Logger) *Hub {
	if logger == nil {
		logger = log.Default()
	}
	return &Hub{
		store:  st,
		logger: logger,
		rooms:  make(map[string]*room),
	}
}

func (h *Hub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	bundle, ok := h.requireSession(w, r)
	if !ok {
		return
	}
	ws, err := upgradeWebSocket(w, r)
	if err != nil {
		return
	}
	connectionID, err := auth.NewToken()
	if err != nil {
		_ = ws.close()
		return
	}
	c := &client{
		connectionID: connectionID,
		userID:       bundle.User.ID,
		deviceID:     bundle.Device.ID,
		ws:           ws,
	}
	defer h.disconnect(c)

	for {
		data, err := ws.readText()
		if err != nil {
			if !errors.Is(err, io.EOF) {
				h.logger.Printf("realtime read error connectionId=%s", c.connectionID)
			}
			return
		}
		var event EventEnvelope
		if err := json.Unmarshal(data, &event); err != nil {
			h.sendError(c, "", "", "invalid_json", "invalid realtime event")
			continue
		}
		h.logger.Printf(
			"realtime event type=%s id=%s conversationId=%s connectionId=%s",
			event.Type,
			event.ID,
			event.ConversationID,
			c.connectionID,
		)
		h.handleEvent(r.Context(), c, event)
	}
}

func (h *Hub) handleEvent(ctx context.Context, c *client, event EventEnvelope) {
	switch event.Type {
	case EventRoomJoin:
		h.handleJoin(ctx, c, event)
	case EventRoomLeave:
		h.handleLeave(c, event)
	case EventPresenceSet:
		h.handlePresenceSet(c, event)
	case EventSignalOffer, EventSignalAnswer, EventSignalICECandidate:
		h.handleSignal(c, event)
	default:
		h.sendError(c, event.ID, event.ConversationID, "unknown_event", "unsupported realtime event")
	}
}

func (h *Hub) handleJoin(ctx context.Context, c *client, event EventEnvelope) {
	if strings.TrimSpace(event.ConversationID) == "" {
		h.sendError(c, event.ID, "", "missing_conversation", "conversationId is required")
		return
	}
	conversation, err := h.authorizedConversation(ctx, c.userID, event.ConversationID)
	if err != nil {
		h.sendError(c, event.ID, event.ConversationID, "forbidden", "conversation is unavailable")
		return
	}
	var payload joinPayload
	if len(event.Payload) > 0 {
		_ = json.Unmarshal(event.Payload, &payload)
	}

	var oldRecipients []*client
	var oldUpdate *presenceUpdatedPayload
	h.mu.Lock()
	if c.conversationID != "" && c.conversationID != conversation.ID {
		oldRecipients, oldUpdate = h.removeClientLocked(c, "left")
	}
	targetRoom := h.ensureRoomLocked(conversation.ID)
	targetRoom.clients[c.connectionID] = c
	c.conversationID = conversation.ID
	c.active = payload.Active
	snapshot := h.snapshotLocked(conversation.ID, targetRoom)
	recipients := h.roomClientsLocked(targetRoom, c.connectionID)
	update := presenceUpdatedPayload{
		ConversationID: conversation.ID,
		ConnectionID:   c.connectionID,
		UserID:         c.userID,
		DeviceID:       c.deviceID,
		Active:         c.active,
		Status:         "joined",
	}
	h.mu.Unlock()

	if oldUpdate != nil {
		h.broadcast(oldRecipients, EventPresenceUpdated, "", oldUpdate.ConversationID, *oldUpdate)
	}
	h.send(c, EventRoomSnapshot, event.ID, conversation.ID, snapshot)
	h.broadcast(recipients, EventPresenceUpdated, "", conversation.ID, update)
}

func (h *Hub) handleLeave(c *client, event EventEnvelope) {
	recipients, update := h.leave(c, "left")
	if update != nil {
		h.broadcast(recipients, EventPresenceUpdated, event.ID, update.ConversationID, *update)
	}
}

func (h *Hub) handlePresenceSet(c *client, event EventEnvelope) {
	var payload joinPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		h.sendError(c, event.ID, event.ConversationID, "invalid_payload", "presence payload is invalid")
		return
	}
	h.mu.Lock()
	if c.conversationID == "" || c.conversationID != event.ConversationID {
		h.mu.Unlock()
		h.sendError(c, event.ID, event.ConversationID, "not_joined", "join the conversation before updating presence")
		return
	}
	c.active = payload.Active
	targetRoom := h.rooms[c.conversationID]
	recipients := h.roomClientsLocked(targetRoom, "")
	update := presenceUpdatedPayload{
		ConversationID: c.conversationID,
		ConnectionID:   c.connectionID,
		UserID:         c.userID,
		DeviceID:       c.deviceID,
		Active:         c.active,
		Status:         "activeChanged",
	}
	h.mu.Unlock()

	h.broadcast(recipients, EventPresenceUpdated, event.ID, c.conversationID, update)
}

func (h *Hub) handleSignal(c *client, event EventEnvelope) {
	var payload map[string]any
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		h.sendError(c, event.ID, event.ConversationID, "invalid_payload", "signaling payload is invalid")
		return
	}
	targetDeviceID, _ := payload["targetDeviceId"].(string)
	targetDeviceID = strings.TrimSpace(targetDeviceID)
	if targetDeviceID == "" {
		h.sendError(c, event.ID, event.ConversationID, "missing_target", "targetDeviceId is required")
		return
	}

	h.mu.Lock()
	if c.conversationID == "" || c.conversationID != event.ConversationID {
		h.mu.Unlock()
		h.sendError(c, event.ID, event.ConversationID, "not_joined", "join the conversation before signaling")
		return
	}
	target := h.findDeviceLocked(event.ConversationID, targetDeviceID)
	h.mu.Unlock()

	if target == nil {
		h.sendError(c, event.ID, event.ConversationID, "target_unavailable", "target device is not joined")
		return
	}

	payload["signalType"] = event.Type
	payload["senderDeviceId"] = c.deviceID
	payload["targetDeviceId"] = targetDeviceID
	h.send(target, EventSignalForwarded, event.ID, event.ConversationID, payload)
}

func (h *Hub) disconnect(c *client) {
	recipients, update := h.leave(c, "left")
	if update != nil {
		h.broadcast(recipients, EventPresenceUpdated, "", update.ConversationID, *update)
	}
	_ = c.ws.close()
}

func (h *Hub) leave(c *client, status string) ([]*client, *presenceUpdatedPayload) {
	h.mu.Lock()
	defer h.mu.Unlock()

	return h.removeClientLocked(c, status)
}

func (h *Hub) removeClientLocked(c *client, status string) ([]*client, *presenceUpdatedPayload) {
	conversationID := c.conversationID
	if conversationID == "" {
		return nil, nil
	}
	targetRoom := h.rooms[conversationID]
	if targetRoom == nil {
		c.conversationID = ""
		c.active = false
		return nil, nil
	}
	delete(targetRoom.clients, c.connectionID)
	if len(targetRoom.clients) == 0 {
		delete(h.rooms, conversationID)
	}
	c.conversationID = ""
	c.active = false
	update := &presenceUpdatedPayload{
		ConversationID: conversationID,
		ConnectionID:   c.connectionID,
		UserID:         c.userID,
		DeviceID:       c.deviceID,
		Active:         false,
		Status:         status,
	}
	return h.roomClientsLocked(targetRoom, ""), update
}

func (h *Hub) authorizedConversation(ctx context.Context, userID string, conversationID string) (store.Conversation, error) {
	conversations, err := h.store.ListConversationsForUser(ctx, userID)
	if err != nil {
		return store.Conversation{}, err
	}
	for _, conversation := range conversations {
		if conversation.ID == conversationID {
			return conversation, nil
		}
	}
	return store.Conversation{}, store.ErrForbidden
}

func (h *Hub) ensureRoomLocked(conversationID string) *room {
	targetRoom := h.rooms[conversationID]
	if targetRoom == nil {
		targetRoom = &room{clients: make(map[string]*client)}
		h.rooms[conversationID] = targetRoom
	}
	return targetRoom
}

func (h *Hub) snapshotLocked(conversationID string, targetRoom *room) roomSnapshotPayload {
	return roomSnapshotPayload{
		ConversationID: conversationID,
		Peers:          h.peersLocked(targetRoom),
		Presence:       h.presenceLocked(targetRoom),
		Floor: floorPayload{
			State:           "idle",
			ActiveSpeakerID: nil,
		},
	}
}

func (h *Hub) peersLocked(targetRoom *room) []peerPayload {
	peers := make([]peerPayload, 0, len(targetRoom.clients))
	for _, c := range targetRoom.clients {
		peers = append(peers, peerPayload{
			ConnectionID: c.connectionID,
			UserID:       c.userID,
			DeviceID:     c.deviceID,
			Active:       c.active,
		})
	}
	sort.Slice(peers, func(i, j int) bool {
		return peers[i].DeviceID < peers[j].DeviceID
	})
	return peers
}

func (h *Hub) presenceLocked(targetRoom *room) presencePayload {
	seen := make(map[string]struct{}, len(targetRoom.clients))
	for _, c := range targetRoom.clients {
		seen[c.userID] = struct{}{}
	}
	userIDs := make([]string, 0, len(seen))
	for userID := range seen {
		userIDs = append(userIDs, userID)
	}
	sort.Strings(userIDs)
	return presencePayload{
		OnlineUserIDs:   userIDs,
		ActiveSpeakerID: nil,
	}
}

func (h *Hub) roomClientsLocked(targetRoom *room, excludedConnectionID string) []*client {
	if targetRoom == nil {
		return nil
	}
	clients := make([]*client, 0, len(targetRoom.clients))
	for _, c := range targetRoom.clients {
		if c.connectionID == excludedConnectionID {
			continue
		}
		clients = append(clients, c)
	}
	return clients
}

func (h *Hub) findDeviceLocked(conversationID string, deviceID string) *client {
	targetRoom := h.rooms[conversationID]
	if targetRoom == nil {
		return nil
	}
	for _, c := range targetRoom.clients {
		if c.deviceID == deviceID {
			return c
		}
	}
	return nil
}

func (h *Hub) broadcast(clients []*client, eventType string, eventID string, conversationID string, payload any) {
	for _, c := range clients {
		h.send(c, eventType, eventID, conversationID, payload)
	}
}

func (h *Hub) send(c *client, eventType string, eventID string, conversationID string, payload any) {
	if eventID == "" {
		eventID = "server-" + time.Now().UTC().Format("20060102150405.000000000")
	}
	body, err := json.Marshal(outboundEnvelope{
		Type:           eventType,
		ID:             eventID,
		ConversationID: conversationID,
		SentAt:         time.Now().UTC().Format(time.RFC3339Nano),
		Payload:        payload,
	})
	if err != nil {
		return
	}
	_ = c.ws.writeText(body)
}

func (h *Hub) sendError(c *client, eventID string, conversationID string, code string, message string) {
	h.send(c, EventError, eventID, conversationID, errorPayload{Code: code, Message: message})
}

func (h *Hub) requireSession(w http.ResponseWriter, r *http.Request) (store.SessionBundle, bool) {
	token := bearerToken(r.Header.Get("Authorization"))
	if token == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing bearer token"})
		return store.SessionBundle{}, false
	}
	bundle, err := h.store.LookupSession(r.Context(), token)
	if err != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return store.SessionBundle{}, false
	}
	return bundle, true
}

func bearerToken(header string) string {
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, prefix))
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
