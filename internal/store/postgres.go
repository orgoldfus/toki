package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"toki/internal/auth"
)

type PostgresStore struct {
	db *sql.DB

	mu            sync.Mutex
	devMagicLinks map[string]string
}

var _ Store = (*PostgresStore)(nil)

func NewPostgresStore(db *sql.DB) *PostgresStore {
	return &PostgresStore{
		db:            db,
		devMagicLinks: make(map[string]string),
	}
}

func (s *PostgresStore) SeedDevelopmentTeam(ctx context.Context, name string, invitedEmails []string) (Team, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Team{}, ErrInvalidInput
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Team{}, err
	}
	defer rollback(tx)

	team, err := s.findOrCreateTeam(ctx, tx, name)
	if err != nil {
		return Team{}, err
	}
	for _, email := range invitedEmails {
		if err := s.addInvitation(ctx, tx, team.ID, email); err != nil {
			return Team{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return Team{}, err
	}
	return team, nil
}

func (s *PostgresStore) CreateMagicLink(ctx context.Context, email string) (string, error) {
	normalized := normalizeEmail(email)
	if normalized == "" {
		return "", ErrInvalidInput
	}

	var exists bool
	err := s.db.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM invitations WHERE email = $1
		)
	`, normalized).Scan(&exists)
	if err != nil {
		return "", err
	}
	if !exists {
		return "", ErrForbidden
	}

	token, err := auth.NewToken()
	if err != nil {
		return "", err
	}
	s.mu.Lock()
	s.devMagicLinks[token] = normalized
	s.mu.Unlock()
	return token, nil
}

func (s *PostgresStore) CreateSession(ctx context.Context, magicToken string, deviceName string) (SessionBundle, error) {
	s.mu.Lock()
	email, ok := s.devMagicLinks[magicToken]
	if ok {
		delete(s.devMagicLinks, magicToken)
	}
	s.mu.Unlock()
	if !ok {
		return SessionBundle{}, ErrForbidden
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return SessionBundle{}, err
	}
	defer rollback(tx)

	user, err := s.findOrCreateUser(ctx, tx, email)
	if err != nil {
		return SessionBundle{}, err
	}
	if err := s.ensureMemberships(ctx, tx, user); err != nil {
		return SessionBundle{}, err
	}

	name := strings.TrimSpace(deviceName)
	if name == "" {
		name = "Mac"
	}
	device := Device{ID: newUUID(), UserID: user.ID, Name: name}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO devices (id, user_id, name)
		VALUES ($1, $2, $3)
		RETURNING created_at
	`, device.ID, device.UserID, device.Name).Scan(&device.CreatedAt)
	if err != nil {
		return SessionBundle{}, err
	}

	sessionToken, err := auth.NewToken()
	if err != nil {
		return SessionBundle{}, err
	}
	session := Session{ID: newUUID(), UserID: user.ID, DeviceID: device.ID, Token: sessionToken}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO sessions (id, user_id, device_id, token_hash)
		VALUES ($1, $2, $3, $4)
		RETURNING created_at, revoked_at
	`, session.ID, session.UserID, session.DeviceID, tokenHash(sessionToken)).Scan(&session.CreatedAt, nullTimeScanner(&session.RevokedAt))
	if err != nil {
		return SessionBundle{}, err
	}

	bundle, err := s.sessionBundle(ctx, tx, session)
	if err != nil {
		return SessionBundle{}, err
	}
	if err := tx.Commit(); err != nil {
		return SessionBundle{}, err
	}
	return bundle, nil
}

func (s *PostgresStore) LookupSession(ctx context.Context, token string) (SessionBundle, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return SessionBundle{}, err
	}
	defer rollback(tx)

	session := Session{Token: token}
	err = tx.QueryRowContext(ctx, `
		SELECT id, user_id, device_id, created_at, revoked_at
		FROM sessions
		WHERE token_hash = $1 AND revoked_at IS NULL
	`, tokenHash(token)).Scan(&session.ID, &session.UserID, &session.DeviceID, &session.CreatedAt, nullTimeScanner(&session.RevokedAt))
	if errors.Is(err, sql.ErrNoRows) {
		return SessionBundle{}, ErrForbidden
	}
	if err != nil {
		return SessionBundle{}, err
	}

	bundle, err := s.sessionBundle(ctx, tx, session)
	if err != nil {
		return SessionBundle{}, err
	}
	if err := tx.Commit(); err != nil {
		return SessionBundle{}, err
	}
	return bundle, nil
}

func (s *PostgresStore) RevokeSession(ctx context.Context, token string) error {
	res, err := s.db.ExecContext(ctx, `
		UPDATE sessions
		SET revoked_at = now()
		WHERE token_hash = $1 AND revoked_at IS NULL
	`, tokenHash(token))
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 1 {
		return nil
	}

	var revokedAt *time.Time
	err = s.db.QueryRowContext(ctx, `
		SELECT revoked_at FROM sessions WHERE token_hash = $1
	`, tokenHash(token)).Scan(nullTimeScanner(&revokedAt))
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if revokedAt != nil {
		return ErrAlreadyRevoked
	}
	return ErrNotFound
}

func (s *PostgresStore) CreateConversation(ctx context.Context, userID string, params CreateConversationParams) (Conversation, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Conversation{}, err
	}
	defer rollback(tx)

	teamID, err := s.firstTeamForUser(ctx, tx, userID)
	if err != nil {
		return Conversation{}, err
	}
	memberIDs := uniqueIDs(append([]string{userID}, params.MemberIDs...))
	if err := s.requireTeamUsers(ctx, tx, teamID, memberIDs); err != nil {
		return Conversation{}, err
	}

	var conversation Conversation
	switch params.Type {
	case ConversationDirect:
		if len(memberIDs) != 2 {
			return Conversation{}, ErrInvalidInput
		}
		conversation, err = s.createDirectConversation(ctx, tx, teamID, memberIDs, params.DisplayName)
	case ConversationGroup:
		if len(memberIDs) < 2 || len(memberIDs) > MaxGroupMembers {
			return Conversation{}, ErrInvalidInput
		}
		conversation, err = s.createGroupConversation(ctx, tx, teamID, memberIDs, params.DisplayName)
	default:
		return Conversation{}, ErrInvalidInput
	}
	if err != nil {
		return Conversation{}, err
	}
	if err := tx.Commit(); err != nil {
		return Conversation{}, err
	}
	return conversation, nil
}

func (s *PostgresStore) ListConversationsForUser(ctx context.Context, userID string) ([]Conversation, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer rollback(tx)

	rows, err := tx.QueryContext(ctx, `
		SELECT c.id
		FROM conversations c
		JOIN conversation_members cm ON cm.conversation_id = c.id
		WHERE cm.user_id = $1
		ORDER BY c.created_at
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	conversations := make([]Conversation, 0, len(ids))
	for _, id := range ids {
		conversation, err := s.loadConversation(ctx, tx, id)
		if err != nil {
			return nil, err
		}
		conversations = append(conversations, conversation)
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return conversations, nil
}

func (s *PostgresStore) AddConversationMembers(ctx context.Context, userID string, conversationID string, memberIDs []string) (Conversation, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Conversation{}, err
	}
	defer rollback(tx)

	if err := lockConversationForUpdate(ctx, tx, conversationID); err != nil {
		return Conversation{}, err
	}

	conversation, err := s.loadConversation(ctx, tx, conversationID)
	if errors.Is(err, sql.ErrNoRows) {
		return Conversation{}, ErrNotFound
	}
	if err != nil {
		return Conversation{}, err
	}
	if conversation.Type != ConversationGroup {
		return Conversation{}, ErrForbidden
	}
	if !conversationHasUser(conversation, userID) {
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
	if err := s.requireTeamUsers(ctx, tx, conversation.TeamID, allIDs); err != nil {
		return Conversation{}, err
	}
	if err := s.addConversationMembers(ctx, tx, conversation.ID, allIDs); err != nil {
		return Conversation{}, err
	}

	conversation, err = s.loadConversation(ctx, tx, conversation.ID)
	if err != nil {
		return Conversation{}, err
	}
	if err := tx.Commit(); err != nil {
		return Conversation{}, err
	}
	return conversation, nil
}

func lockConversationForUpdate(ctx context.Context, tx *sql.Tx, conversationID string) error {
	_, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1)::bigint)`, conversationID)
	return err
}

func (s *PostgresStore) findOrCreateTeam(ctx context.Context, tx *sql.Tx, name string) (Team, error) {
	var team Team
	err := tx.QueryRowContext(ctx, `
		SELECT id, name, created_at
		FROM teams
		WHERE name = $1
		ORDER BY created_at
		LIMIT 1
	`, name).Scan(&team.ID, &team.Name, &team.CreatedAt)
	if err == nil {
		return team, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Team{}, err
	}

	team = Team{ID: newUUID(), Name: name}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO teams (id, name)
		VALUES ($1, $2)
		RETURNING created_at
	`, team.ID, team.Name).Scan(&team.CreatedAt)
	if err != nil {
		return Team{}, err
	}
	return team, nil
}

func (s *PostgresStore) addInvitation(ctx context.Context, tx *sql.Tx, teamID string, email string) error {
	normalized := normalizeEmail(email)
	if normalized == "" {
		return ErrInvalidInput
	}
	_, err := tx.ExecContext(ctx, `
		INSERT INTO invitations (id, team_id, email)
		VALUES ($1, $2, $3)
		ON CONFLICT (team_id, email) DO NOTHING
	`, newUUID(), teamID, normalized)
	return err
}

func (s *PostgresStore) findOrCreateUser(ctx context.Context, tx *sql.Tx, email string) (User, error) {
	user := User{ID: newUUID(), Email: email}
	err := tx.QueryRowContext(ctx, `
		INSERT INTO users (id, email)
		VALUES ($1, $2)
		ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
		RETURNING id, email, created_at
	`, user.ID, user.Email).Scan(&user.ID, &user.Email, &user.CreatedAt)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *PostgresStore) ensureMemberships(ctx context.Context, tx *sql.Tx, user User) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT id, team_id
		FROM invitations
		WHERE email = $1
	`, user.Email)
	if err != nil {
		return err
	}
	defer rows.Close()

	type invitationRef struct {
		id     string
		teamID string
	}
	var invitations []invitationRef
	for rows.Next() {
		var invitation invitationRef
		if err := rows.Scan(&invitation.id, &invitation.teamID); err != nil {
			return err
		}
		invitations = append(invitations, invitation)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(invitations) == 0 {
		return ErrForbidden
	}

	for _, invitation := range invitations {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO memberships (id, team_id, user_id, role)
			VALUES ($1, $2, $3, 'member')
			ON CONFLICT (team_id, user_id) DO NOTHING
		`, newUUID(), invitation.teamID, user.ID)
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `
			UPDATE invitations
			SET accepted_at = COALESCE(accepted_at, now())
			WHERE id = $1
		`, invitation.id)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *PostgresStore) sessionBundle(ctx context.Context, tx *sql.Tx, session Session) (SessionBundle, error) {
	var bundle SessionBundle
	bundle.Session = session

	err := tx.QueryRowContext(ctx, `
		SELECT id, email, created_at FROM users WHERE id = $1
	`, session.UserID).Scan(&bundle.User.ID, &bundle.User.Email, &bundle.User.CreatedAt)
	if err != nil {
		return SessionBundle{}, err
	}
	err = tx.QueryRowContext(ctx, `
		SELECT id, user_id, name, created_at FROM devices WHERE id = $1
	`, session.DeviceID).Scan(&bundle.Device.ID, &bundle.Device.UserID, &bundle.Device.Name, &bundle.Device.CreatedAt)
	if err != nil {
		return SessionBundle{}, err
	}

	memberships, teams, err := s.membershipsAndTeams(ctx, tx, session.UserID)
	if err != nil {
		return SessionBundle{}, err
	}
	bundle.Memberships = memberships
	bundle.Teams = teams

	devices, err := s.devicesForUser(ctx, tx, session.UserID)
	if err != nil {
		return SessionBundle{}, err
	}
	bundle.Devices = devices

	return bundle, nil
}

func (s *PostgresStore) membershipsAndTeams(ctx context.Context, tx *sql.Tx, userID string) ([]Membership, []Team, error) {
	rows, err := tx.QueryContext(ctx, `
		SELECT m.id, m.team_id, m.user_id, m.role, m.created_at, t.id, t.name, t.created_at
		FROM memberships m
		JOIN teams t ON t.id = m.team_id
		WHERE m.user_id = $1
		ORDER BY m.created_at
	`, userID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var memberships []Membership
	var teams []Team
	for rows.Next() {
		var membership Membership
		var team Team
		err := rows.Scan(
			&membership.ID, &membership.TeamID, &membership.UserID, &membership.Role, &membership.CreatedAt,
			&team.ID, &team.Name, &team.CreatedAt,
		)
		if err != nil {
			return nil, nil, err
		}
		memberships = append(memberships, membership)
		teams = append(teams, team)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	return memberships, teams, nil
}

func (s *PostgresStore) devicesForUser(ctx context.Context, tx *sql.Tx, userID string) ([]Device, error) {
	rows, err := tx.QueryContext(ctx, `
		SELECT id, user_id, name, created_at
		FROM devices
		WHERE user_id = $1
		ORDER BY created_at
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []Device
	for rows.Next() {
		var device Device
		if err := rows.Scan(&device.ID, &device.UserID, &device.Name, &device.CreatedAt); err != nil {
			return nil, err
		}
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return devices, nil
}

func (s *PostgresStore) firstTeamForUser(ctx context.Context, tx *sql.Tx, userID string) (string, error) {
	var teamID string
	err := tx.QueryRowContext(ctx, `
		SELECT team_id
		FROM memberships
		WHERE user_id = $1
		ORDER BY created_at
		LIMIT 1
	`, userID).Scan(&teamID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrForbidden
	}
	if err != nil {
		return "", err
	}
	return teamID, nil
}

func (s *PostgresStore) requireTeamUsers(ctx context.Context, tx *sql.Tx, teamID string, userIDs []string) error {
	for _, userID := range userIDs {
		var exists bool
		err := tx.QueryRowContext(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM memberships WHERE team_id = $1 AND user_id = $2
			)
		`, teamID, userID).Scan(&exists)
		if err != nil {
			return err
		}
		if !exists {
			return ErrInvalidInput
		}
	}
	return nil
}

func (s *PostgresStore) createDirectConversation(ctx context.Context, tx *sql.Tx, teamID string, memberIDs []string, displayName string) (Conversation, error) {
	low, high := sortedPair(memberIDs)
	conversation := Conversation{ID: newUUID()}
	err := tx.QueryRowContext(ctx, `
		INSERT INTO conversations (id, team_id, type, display_name, direct_user_id_low, direct_user_id_high)
		VALUES ($1, $2, 'direct', NULLIF($3, ''), $4, $5)
		ON CONFLICT (team_id, direct_user_id_low, direct_user_id_high) WHERE type = 'direct'
		DO UPDATE SET display_name = conversations.display_name
		RETURNING id, team_id, type, COALESCE(display_name, ''), created_at
	`, conversation.ID, teamID, strings.TrimSpace(displayName), low, high).Scan(
		&conversation.ID, &conversation.TeamID, &conversation.Type, &conversation.DisplayName, &conversation.CreatedAt,
	)
	if err != nil {
		return Conversation{}, err
	}
	if err := s.addConversationMembers(ctx, tx, conversation.ID, memberIDs); err != nil {
		return Conversation{}, err
	}
	return s.loadConversation(ctx, tx, conversation.ID)
}

func (s *PostgresStore) createGroupConversation(ctx context.Context, tx *sql.Tx, teamID string, memberIDs []string, displayName string) (Conversation, error) {
	conversation := Conversation{ID: newUUID()}
	err := tx.QueryRowContext(ctx, `
		INSERT INTO conversations (id, team_id, type, display_name)
		VALUES ($1, $2, 'group', NULLIF($3, ''))
		RETURNING id, team_id, type, COALESCE(display_name, ''), created_at
	`, conversation.ID, teamID, strings.TrimSpace(displayName)).Scan(
		&conversation.ID, &conversation.TeamID, &conversation.Type, &conversation.DisplayName, &conversation.CreatedAt,
	)
	if err != nil {
		return Conversation{}, err
	}
	if err := s.addConversationMembers(ctx, tx, conversation.ID, memberIDs); err != nil {
		return Conversation{}, err
	}
	return s.loadConversation(ctx, tx, conversation.ID)
}

func (s *PostgresStore) addConversationMembers(ctx context.Context, tx *sql.Tx, conversationID string, userIDs []string) error {
	for _, userID := range uniqueIDs(userIDs) {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO conversation_members (id, conversation_id, user_id)
			VALUES ($1, $2, $3)
			ON CONFLICT (conversation_id, user_id) DO NOTHING
		`, newUUID(), conversationID, userID)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *PostgresStore) loadConversation(ctx context.Context, tx *sql.Tx, conversationID string) (Conversation, error) {
	var conversation Conversation
	err := tx.QueryRowContext(ctx, `
		SELECT id, team_id, type, COALESCE(display_name, ''), created_at
		FROM conversations
		WHERE id = $1
	`, conversationID).Scan(&conversation.ID, &conversation.TeamID, &conversation.Type, &conversation.DisplayName, &conversation.CreatedAt)
	if err != nil {
		return Conversation{}, err
	}

	rows, err := tx.QueryContext(ctx, `
		SELECT cm.id, cm.user_id, u.email, cm.created_at
		FROM conversation_members cm
		JOIN users u ON u.id = cm.user_id
		WHERE cm.conversation_id = $1
		ORDER BY u.email
	`, conversation.ID)
	if err != nil {
		return Conversation{}, err
	}
	defer rows.Close()

	for rows.Next() {
		var member ConversationMember
		if err := rows.Scan(&member.ID, &member.UserID, &member.Email, &member.CreatedAt); err != nil {
			return Conversation{}, err
		}
		conversation.Members = append(conversation.Members, member)
	}
	if err := rows.Err(); err != nil {
		return Conversation{}, err
	}
	return conversation, nil
}

func rollback(tx *sql.Tx) {
	_ = tx.Rollback()
}

func newUUID() string {
	return uuid.NewString()
}

func tokenHash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func sortedPair(ids []string) (string, string) {
	cp := append([]string(nil), ids...)
	sort.Strings(cp)
	return cp[0], cp[1]
}

func nullTimeScanner(dest **time.Time) sql.Scanner {
	return nullTime{dest: dest}
}

type nullTime struct {
	dest **time.Time
}

func (n nullTime) Scan(value any) error {
	if value == nil {
		*n.dest = nil
		return nil
	}
	var t time.Time
	switch v := value.(type) {
	case time.Time:
		t = v
	case string:
		parsed, err := time.Parse(time.RFC3339Nano, v)
		if err != nil {
			return err
		}
		t = parsed
	case []byte:
		parsed, err := time.Parse(time.RFC3339Nano, string(v))
		if err != nil {
			return err
		}
		t = parsed
	default:
		return errors.New("unsupported time value")
	}
	*n.dest = &t
	return nil
}
