package realtime

import (
	"encoding/json"
	"time"
)

const (
	EventRoomJoin           = "room.join"
	EventRoomLeave          = "room.leave"
	EventPresenceSet        = "presence.set"
	EventRoomSnapshot       = "room.snapshot"
	EventPresenceUpdated    = "presence.updated"
	EventSignalOffer        = "signal.offer"
	EventSignalAnswer       = "signal.answer"
	EventSignalICECandidate = "signal.iceCandidate"
	EventSignalForwarded    = "signal.forwarded"
	EventError              = "error"
	EventReconnectRequired  = "reconnect.required"
)

type EventEnvelope struct {
	Type           string          `json:"type"`
	ID             string          `json:"id"`
	ConversationID string          `json:"conversationId,omitempty"`
	SentAt         time.Time       `json:"sentAt"`
	Payload        json.RawMessage `json:"payload"`
}

type outboundEnvelope struct {
	Type           string `json:"type"`
	ID             string `json:"id"`
	ConversationID string `json:"conversationId,omitempty"`
	SentAt         string `json:"sentAt"`
	Payload        any    `json:"payload"`
}

type joinPayload struct {
	Active bool `json:"active"`
}

type peerPayload struct {
	ConnectionID string `json:"connectionId"`
	UserID       string `json:"userId"`
	DeviceID     string `json:"deviceId"`
	Active       bool   `json:"active"`
}

type presencePayload struct {
	OnlineUserIDs   []string `json:"onlineUserIds"`
	ActiveSpeakerID *string  `json:"activeSpeakerId"`
}

type floorPayload struct {
	State           string  `json:"state"`
	ActiveSpeakerID *string `json:"activeSpeakerId"`
}

type roomSnapshotPayload struct {
	ConversationID string          `json:"conversationId"`
	Peers          []peerPayload   `json:"peers"`
	Presence       presencePayload `json:"presence"`
	Floor          floorPayload    `json:"floor"`
}

type presenceUpdatedPayload struct {
	ConversationID string `json:"conversationId"`
	ConnectionID   string `json:"connectionId"`
	UserID         string `json:"userId"`
	DeviceID       string `json:"deviceId"`
	Active         bool   `json:"active"`
	Status         string `json:"status"`
}

type errorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
