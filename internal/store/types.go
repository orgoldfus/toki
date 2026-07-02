package store

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotFound       = errors.New("not found")
	ErrForbidden      = errors.New("forbidden")
	ErrInvalidInput   = errors.New("invalid input")
	ErrAlreadyRevoked = errors.New("already revoked")
)

const (
	ConversationDirect = "direct"
	ConversationGroup  = "group"
	MaxGroupMembers    = 10
)

type Store interface {
	SeedDevelopmentTeam(ctx context.Context, name string, invitedEmails []string) (Team, error)
	CreateMagicLink(ctx context.Context, email string) (string, error)
	CreateSession(ctx context.Context, magicToken string, deviceName string) (SessionBundle, error)
	LookupSession(ctx context.Context, token string) (SessionBundle, error)
	RevokeSession(ctx context.Context, token string) error
	CreateConversation(ctx context.Context, userID string, params CreateConversationParams) (Conversation, error)
	ListConversationsForUser(ctx context.Context, userID string) ([]Conversation, error)
	AddConversationMembers(ctx context.Context, userID string, conversationID string, memberIDs []string) (Conversation, error)
}

type Team struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"createdAt"`
}

type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"createdAt"`
}

type Membership struct {
	ID        string    `json:"id"`
	TeamID    string    `json:"teamId"`
	UserID    string    `json:"userId"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
}

type Invitation struct {
	ID        string    `json:"id"`
	TeamID    string    `json:"teamId"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"createdAt"`
	AcceptedAt *time.Time `json:"acceptedAt,omitempty"`
}

type Device struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"createdAt"`
}

type Session struct {
	ID        string     `json:"id"`
	UserID    string     `json:"userId"`
	DeviceID  string     `json:"deviceId"`
	Token     string     `json:"-"`
	CreatedAt time.Time  `json:"createdAt"`
	RevokedAt *time.Time `json:"revokedAt,omitempty"`
}

type SessionBundle struct {
	Session     Session      `json:"session"`
	User        User         `json:"user"`
	Device      Device       `json:"device"`
	Memberships []Membership `json:"memberships"`
	Devices     []Device     `json:"devices"`
	Teams       []Team       `json:"teams"`
}

type Conversation struct {
	ID              string               `json:"id"`
	TeamID          string               `json:"teamId"`
	Type            string               `json:"type"`
	DisplayName     string               `json:"displayName,omitempty"`
	Members         []ConversationMember `json:"members"`
	CreatedAt       time.Time            `json:"createdAt"`
	PresenceSummary  PresenceSummary      `json:"lastPresenceSummary"`
}

type ConversationMember struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"createdAt"`
}

type PresenceSummary struct {
	OnlineCount int `json:"onlineCount"`
}

type CreateConversationParams struct {
	Type        string
	MemberIDs   []string
	DisplayName string
}
