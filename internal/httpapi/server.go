package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"toki/internal/realtime"
	"toki/internal/store"
)

type Server struct {
	store    store.Store
	realtime *realtime.Hub
	mux      *http.ServeMux
	logger   *PrivacySafeLogger
}

type userResponse struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"displayName"`
}

type teamResponse struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
}

type teamMembershipResponse struct {
	ID   string       `json:"id"`
	Team teamResponse `json:"team"`
	Role string       `json:"role"`
}

type deviceResponse struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type conversationMemberResponse struct {
	User userResponse `json:"user"`
	Role string       `json:"role"`
}

type presenceResponse struct {
	OnlineUserIDs   []string `json:"onlineUserIds"`
	ActiveSpeakerID *string  `json:"activeSpeakerId"`
}

type iceConfigResponse struct {
	ICEServers  []iceConfigServerResponse `json:"iceServers"`
	RelayPolicy string                    `json:"relayPolicy"`
}

type iceConfigServerResponse struct {
	URLs []string `json:"urls"`
}

type conversationResponse struct {
	ID           string                       `json:"id"`
	Type         string                       `json:"type"`
	DisplayName  *string                      `json:"displayName"`
	Members      []conversationMemberResponse `json:"members"`
	LastPresence presenceResponse             `json:"lastPresence"`
}

func NewServer(st store.Store) http.Handler {
	s := &Server{
		store:    st,
		realtime: realtime.NewHub(st, nil),
		mux:      http.NewServeMux(),
		logger:   NewPrivacySafeLogger(slogDefaultHandler()),
	}
	s.routes()
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	recorder := &statusRecordingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
	s.mux.ServeHTTP(recorder, r)
	s.logger.RequestCompleted(r, PrivacySafeLogFields{
		StatusCode: recorder.statusCode,
		EventType:  eventTypeForRequest(r),
	})
}

func (s *Server) routes() {
	s.mux.HandleFunc("POST /v1/auth/magic-link", s.handleMagicLink)
	s.mux.HandleFunc("POST /v1/auth/session", s.handleSession)
	s.mux.HandleFunc("GET /v1/me", s.handleMe)
	s.mux.HandleFunc("GET /v1/ice-config", s.handleIceConfig)
	s.mux.HandleFunc("GET /v1/realtime", s.realtime.ServeHTTP)
	s.mux.HandleFunc("GET /v1/conversations", s.handleListConversations)
	s.mux.HandleFunc("POST /v1/conversations", s.handleCreateConversation)
	s.mux.HandleFunc("POST /v1/conversations/", s.handleConversationMembers)
}

func (s *Server) handleMagicLink(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	token, err := s.store.CreateMagicLink(r.Context(), req.Email)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"token": token})
}

func (s *Server) handleSession(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token      string `json:"token"`
		DeviceName string `json:"deviceName"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	bundle, err := s.store.CreateSession(r.Context(), req.Token, req.DeviceName)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"sessionToken":    bundle.Session.Token,
		"user":            apiUser(bundle.User),
		"device":          apiDevice(bundle.Device),
		"teamMemberships": apiMemberships(bundle),
	})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	bundle, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":            apiUser(bundle.User),
		"teamMemberships": apiMemberships(bundle),
		"devices":         apiDevices(bundle.Devices),
	})
}

func (s *Server) handleIceConfig(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireSession(w, r); !ok {
		return
	}
	writeJSON(w, http.StatusOK, iceConfigResponse{
		ICEServers: []iceConfigServerResponse{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
		RelayPolicy: "disabled",
	})
}

func (s *Server) handleListConversations(w http.ResponseWriter, r *http.Request) {
	bundle, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	conversations, err := s.store.ListConversationsForUser(r.Context(), bundle.User.ID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversations": apiConversations(conversations)})
}

func (s *Server) handleCreateConversation(w http.ResponseWriter, r *http.Request) {
	bundle, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	var req struct {
		Type        string   `json:"type"`
		MemberIDs   []string `json:"memberIds"`
		DisplayName string   `json:"displayName"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	conversation, err := s.store.CreateConversation(r.Context(), bundle.User.ID, store.CreateConversationParams{
		Type:        req.Type,
		MemberIDs:   req.MemberIDs,
		DisplayName: req.DisplayName,
	})
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"conversation": apiConversation(conversation)})
}

func (s *Server) handleConversationMembers(w http.ResponseWriter, r *http.Request) {
	bundle, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	conversationID, ok := conversationIDFromMembersPath(r.URL.Path)
	if !ok {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	var req struct {
		MemberIDs []string `json:"memberIds"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	conversation, err := s.store.AddConversationMembers(r.Context(), bundle.User.ID, conversationID, req.MemberIDs)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversation": apiConversation(conversation)})
}

func (s *Server) requireSession(w http.ResponseWriter, r *http.Request) (store.SessionBundle, bool) {
	token := bearerToken(r.Header.Get("Authorization"))
	if token == "" {
		writeError(w, http.StatusUnauthorized, "missing bearer token")
		return store.SessionBundle{}, false
	}
	bundle, err := s.store.LookupSession(r.Context(), token)
	if err != nil {
		writeStoreError(w, err)
		return store.SessionBundle{}, false
	}
	return bundle, true
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrForbidden):
		writeError(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, store.ErrInvalidInput), errors.Is(err, store.ErrAlreadyRevoked):
		writeError(w, http.StatusBadRequest, "invalid request")
	default:
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func bearerToken(header string) string {
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, prefix))
}

func conversationIDFromMembersPath(path string) (string, bool) {
	const prefix = "/v1/conversations/"
	const suffix = "/members"
	if !strings.HasPrefix(path, prefix) || !strings.HasSuffix(path, suffix) {
		return "", false
	}
	id := strings.TrimSuffix(strings.TrimPrefix(path, prefix), suffix)
	id = strings.Trim(id, "/")
	return id, id != ""
}

func apiUser(user store.User) userResponse {
	return userResponse{
		ID:          user.ID,
		Email:       user.Email,
		DisplayName: displayNameFromEmail(user.Email),
	}
}

func apiDevice(device store.Device) deviceResponse {
	return deviceResponse{ID: device.ID, Name: device.Name}
}

func apiDevices(devices []store.Device) []deviceResponse {
	out := make([]deviceResponse, 0, len(devices))
	for _, device := range devices {
		out = append(out, apiDevice(device))
	}
	return out
}

func apiMemberships(bundle store.SessionBundle) []teamMembershipResponse {
	teams := make(map[string]store.Team, len(bundle.Teams))
	for _, team := range bundle.Teams {
		teams[team.ID] = team
	}

	out := make([]teamMembershipResponse, 0, len(bundle.Memberships))
	for _, membership := range bundle.Memberships {
		team := teams[membership.TeamID]
		out = append(out, teamMembershipResponse{
			ID: membership.ID,
			Team: teamResponse{
				ID:          membership.TeamID,
				DisplayName: team.Name,
			},
			Role: membership.Role,
		})
	}
	return out
}

func apiConversations(conversations []store.Conversation) []conversationResponse {
	out := make([]conversationResponse, 0, len(conversations))
	for _, conversation := range conversations {
		out = append(out, apiConversation(conversation))
	}
	return out
}

func apiConversation(conversation store.Conversation) conversationResponse {
	var displayName *string
	if conversation.DisplayName != "" {
		name := conversation.DisplayName
		displayName = &name
	}

	members := make([]conversationMemberResponse, 0, len(conversation.Members))
	for _, member := range conversation.Members {
		members = append(members, conversationMemberResponse{
			User: userResponse{
				ID:          member.UserID,
				Email:       member.Email,
				DisplayName: displayNameFromEmail(member.Email),
			},
			Role: "member",
		})
	}

	return conversationResponse{
		ID:          conversation.ID,
		Type:        conversation.Type,
		DisplayName: displayName,
		Members:     members,
		LastPresence: presenceResponse{
			OnlineUserIDs:   []string{},
			ActiveSpeakerID: nil,
		},
	}
}

func displayNameFromEmail(email string) string {
	name := strings.TrimSpace(email)
	if at := strings.IndexByte(name, '@'); at > 0 {
		name = name[:at]
	}
	if name == "" {
		return "Toki User"
	}
	return name
}

func eventTypeForRequest(r *http.Request) string {
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/v1/auth/magic-link":
		return "auth.magic_link"
	case r.Method == http.MethodPost && r.URL.Path == "/v1/auth/session":
		return "auth.session"
	case r.Method == http.MethodGet && r.URL.Path == "/v1/me":
		return "auth.me"
	case r.Method == http.MethodGet && r.URL.Path == "/v1/ice-config":
		return "media.ice_config"
	case r.Method == http.MethodGet && r.URL.Path == "/v1/realtime":
		return "realtime.websocket"
	case r.Method == http.MethodGet && r.URL.Path == "/v1/conversations":
		return "conversation.list"
	case r.Method == http.MethodPost && r.URL.Path == "/v1/conversations":
		return "conversation.create"
	case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/v1/conversations/"):
		return "conversation.members"
	default:
		return "request"
	}
}

func slogDefaultHandler() slog.Handler {
	return slog.Default().Handler()
}
