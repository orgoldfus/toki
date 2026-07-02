package store

import (
	"context"
	"sort"
	"strings"
	"sync"
	"time"

	"toki/internal/auth"
)

type MemoryStore struct {
	mu sync.Mutex

	nextID int

	teams         map[string]Team
	users         map[string]User
	usersByEmail  map[string]string
	memberships   map[string]Membership
	invitations   map[string]Invitation
	invitesByEmail map[string]string
	devMagicLinks map[string]string
	sessions      map[string]Session
	devices       map[string]Device
	conversations map[string]Conversation
	directByPair  map[string]string
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		teams:          make(map[string]Team),
		users:          make(map[string]User),
		usersByEmail:   make(map[string]string),
		memberships:    make(map[string]Membership),
		invitations:    make(map[string]Invitation),
		invitesByEmail: make(map[string]string),
		devMagicLinks:  make(map[string]string),
		sessions:       make(map[string]Session),
		devices:        make(map[string]Device),
		conversations:  make(map[string]Conversation),
		directByPair:   make(map[string]string),
	}
}

func (s *MemoryStore) SeedDevelopmentTeam(ctx context.Context, name string, invitedEmails []string) (Team, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	team := Team{ID: s.id("team"), Name: strings.TrimSpace(name), CreatedAt: time.Now().UTC()}
	if team.Name == "" {
		return Team{}, ErrInvalidInput
	}
	s.teams[team.ID] = team
	for _, email := range invitedEmails {
		if err := s.addInvitationLocked(team.ID, email); err != nil {
			return Team{}, err
		}
	}
	return team, nil
}

func (s *MemoryStore) CreateMagicLink(ctx context.Context, email string) (string, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	normalized := normalizeEmail(email)
	if normalized == "" {
		return "", ErrInvalidInput
	}
	if _, ok := s.invitesByEmail[normalized]; !ok {
		return "", ErrForbidden
	}
	token, err := auth.NewToken()
	if err != nil {
		return "", err
	}
	s.devMagicLinks[token] = normalized
	return token, nil
}

func (s *MemoryStore) CreateSession(ctx context.Context, magicToken string, deviceName string) (SessionBundle, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	email, ok := s.devMagicLinks[magicToken]
	if !ok {
		return SessionBundle{}, ErrForbidden
	}
	delete(s.devMagicLinks, magicToken)

	user, err := s.ensureUserLocked(email)
	if err != nil {
		return SessionBundle{}, err
	}
	if err := s.ensureMembershipLocked(user); err != nil {
		return SessionBundle{}, err
	}

	device := Device{
		ID:        s.id("device"),
		UserID:    user.ID,
		Name:      strings.TrimSpace(deviceName),
		CreatedAt: time.Now().UTC(),
	}
	if device.Name == "" {
		device.Name = "Mac"
	}
	s.devices[device.ID] = device

	sessionToken, err := auth.NewToken()
	if err != nil {
		return SessionBundle{}, err
	}
	session := Session{
		ID:        s.id("session"),
		UserID:    user.ID,
		DeviceID:  device.ID,
		Token:     sessionToken,
		CreatedAt: time.Now().UTC(),
	}
	s.sessions[sessionToken] = session

	return s.bundleLocked(session), nil
}

func (s *MemoryStore) LookupSession(ctx context.Context, token string) (SessionBundle, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	session, ok := s.sessions[token]
	if !ok || session.RevokedAt != nil {
		return SessionBundle{}, ErrForbidden
	}
	return s.bundleLocked(session), nil
}

func (s *MemoryStore) RevokeSession(ctx context.Context, token string) error {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	session, ok := s.sessions[token]
	if !ok {
		return ErrNotFound
	}
	if session.RevokedAt != nil {
		return ErrAlreadyRevoked
	}
	now := time.Now().UTC()
	session.RevokedAt = &now
	s.sessions[token] = session
	return nil
}

func (s *MemoryStore) CreateConversation(ctx context.Context, userID string, params CreateConversationParams) (Conversation, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	user, ok := s.users[userID]
	if !ok {
		return Conversation{}, ErrForbidden
	}
	teamID, ok := s.firstTeamForUserLocked(userID)
	if !ok {
		return Conversation{}, ErrForbidden
	}
	memberIDs := uniqueIDs(append([]string{userID}, params.MemberIDs...))
	if err := s.requireTeamUsersLocked(teamID, memberIDs); err != nil {
		return Conversation{}, err
	}

	switch params.Type {
	case ConversationDirect:
		if len(memberIDs) != 2 {
			return Conversation{}, ErrInvalidInput
		}
		pair := directPairKey(memberIDs)
		if id, ok := s.directByPair[pair]; ok {
			return s.conversations[id], nil
		}
	case ConversationGroup:
		if len(memberIDs) < 2 || len(memberIDs) > MaxGroupMembers {
			return Conversation{}, ErrInvalidInput
		}
	default:
		return Conversation{}, ErrInvalidInput
	}

	conversation := Conversation{
		ID:          s.id("conversation"),
		TeamID:      teamID,
		Type:        params.Type,
		DisplayName: strings.TrimSpace(params.DisplayName),
		CreatedAt:   time.Now().UTC(),
	}
	conversation.Members = s.membersForUsersLocked(memberIDs)
	s.conversations[conversation.ID] = conversation
	if params.Type == ConversationDirect {
		s.directByPair[directPairKey(memberIDs)] = conversation.ID
	}
	_ = user
	return conversation, nil
}

func (s *MemoryStore) ListConversationsForUser(ctx context.Context, userID string) ([]Conversation, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	var out []Conversation
	for _, conversation := range s.conversations {
		if conversationHasUser(conversation, userID) {
			out = append(out, conversation)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.Before(out[j].CreatedAt)
	})
	return out, nil
}

func (s *MemoryStore) AddConversationMembers(ctx context.Context, userID string, conversationID string, memberIDs []string) (Conversation, error) {
	_ = ctx

	s.mu.Lock()
	defer s.mu.Unlock()

	conversation, ok := s.conversations[conversationID]
	if !ok {
		return Conversation{}, ErrNotFound
	}
	if conversation.Type != ConversationGroup || !conversationHasUser(conversation, userID) {
		return Conversation{}, ErrForbidden
	}

	allIDs := make([]string, 0, len(conversation.Members)+len(memberIDs))
	for _, member := range conversation.Members {
		allIDs = append(allIDs, member.UserID)
	}
	allIDs = uniqueIDs(append(allIDs, memberIDs...))
	if len(allIDs) > MaxGroupMembers {
		return Conversation{}, ErrInvalidInput
	}
	if err := s.requireTeamUsersLocked(conversation.TeamID, allIDs); err != nil {
		return Conversation{}, err
	}

	conversation.Members = s.membersForUsersLocked(allIDs)
	s.conversations[conversation.ID] = conversation
	return conversation, nil
}

func (s *MemoryStore) addInvitationLocked(teamID string, email string) error {
	normalized := normalizeEmail(email)
	if normalized == "" {
		return ErrInvalidInput
	}
	if _, ok := s.invitesByEmail[normalized]; ok {
		return nil
	}
	invitation := Invitation{
		ID:        s.id("invitation"),
		TeamID:    teamID,
		Email:     normalized,
		CreatedAt: time.Now().UTC(),
	}
	s.invitations[invitation.ID] = invitation
	s.invitesByEmail[normalized] = invitation.ID
	return nil
}

func (s *MemoryStore) ensureUserLocked(email string) (User, error) {
	if id, ok := s.usersByEmail[email]; ok {
		return s.users[id], nil
	}
	user := User{ID: s.id("user"), Email: email, CreatedAt: time.Now().UTC()}
	s.users[user.ID] = user
	s.usersByEmail[email] = user.ID
	return user, nil
}

func (s *MemoryStore) ensureMembershipLocked(user User) error {
	inviteID, ok := s.invitesByEmail[user.Email]
	if !ok {
		return ErrForbidden
	}
	invitation := s.invitations[inviteID]
	for _, membership := range s.memberships {
		if membership.TeamID == invitation.TeamID && membership.UserID == user.ID {
			return nil
		}
	}
	membership := Membership{
		ID:        s.id("membership"),
		TeamID:    invitation.TeamID,
		UserID:    user.ID,
		Role:      "member",
		CreatedAt: time.Now().UTC(),
	}
	s.memberships[membership.ID] = membership
	now := time.Now().UTC()
	invitation.AcceptedAt = &now
	s.invitations[inviteID] = invitation
	return nil
}

func (s *MemoryStore) firstTeamForUserLocked(userID string) (string, bool) {
	for _, membership := range s.memberships {
		if membership.UserID == userID {
			return membership.TeamID, true
		}
	}
	return "", false
}

func (s *MemoryStore) requireTeamUsersLocked(teamID string, userIDs []string) error {
	for _, userID := range userIDs {
		found := false
		for _, membership := range s.memberships {
			if membership.TeamID == teamID && membership.UserID == userID {
				found = true
				break
			}
		}
		if !found {
			return ErrInvalidInput
		}
	}
	return nil
}

func (s *MemoryStore) membersForUsersLocked(userIDs []string) []ConversationMember {
	sort.Strings(userIDs)
	members := make([]ConversationMember, 0, len(userIDs))
	for _, userID := range userIDs {
		user := s.users[userID]
		members = append(members, ConversationMember{
			ID:        s.id("conversation_member"),
			UserID:    user.ID,
			Email:     user.Email,
			CreatedAt: time.Now().UTC(),
		})
	}
	return members
}

func (s *MemoryStore) bundleLocked(session Session) SessionBundle {
	bundle := SessionBundle{
		Session: session,
		User:    s.users[session.UserID],
		Device:  s.devices[session.DeviceID],
	}
	for _, membership := range s.memberships {
		if membership.UserID == session.UserID {
			bundle.Memberships = append(bundle.Memberships, membership)
			if team, ok := s.teams[membership.TeamID]; ok {
				bundle.Teams = append(bundle.Teams, team)
			}
		}
	}
	for _, device := range s.devices {
		if device.UserID == session.UserID {
			bundle.Devices = append(bundle.Devices, device)
		}
	}
	return bundle
}

func (s *MemoryStore) id(prefix string) string {
	s.nextID++
	return prefix + "_" + strconvID(s.nextID)
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func uniqueIDs(ids []string) []string {
	seen := make(map[string]struct{}, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func directPairKey(ids []string) string {
	cp := append([]string(nil), ids...)
	sort.Strings(cp)
	return strings.Join(cp, ":")
}

func conversationHasUser(conversation Conversation, userID string) bool {
	for _, member := range conversation.Members {
		if member.UserID == userID {
			return true
		}
	}
	return false
}

func strconvID(id int) string {
	if id == 0 {
		return "0"
	}
	var digits [20]byte
	i := len(digits)
	for id > 0 {
		i--
		digits[i] = byte('0' + id%10)
		id /= 10
	}
	return string(digits[i:])
}
