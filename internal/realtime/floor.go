package realtime

import (
	"fmt"
	"sync"
	"time"

	"toki/internal/auth"
)

const (
	floorDeniedBusy        = "busy"
	floorReleasedReleased  = "released"
	floorReleasedDisconnect = "disconnect"
	floorReleasedTimeout   = "timeout"
	floorReleasedServerReset = "server_reset"
)

type floorRequester struct {
	connectionID string
	userID       string
	deviceID     string
}

type floorLease struct {
	conversationID string
	tokenID        string
	connectionID   string
	speakerUserID  string
	speakerDeviceID string
	grantedAt      time.Time
	expiresAt      time.Time
}

type floorRegistry struct {
	mu  sync.Mutex
	ttl time.Duration
	byConversation map[string]floorLease
}

func newFloorRegistry(ttl time.Duration) *floorRegistry {
	return &floorRegistry{
		ttl:            ttl,
		byConversation: make(map[string]floorLease),
	}
}

func (r *floorRegistry) request(conversationID string, requester floorRequester, now time.Time) (floorGrantPayload, *floorDeniedPayload) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.expireLocked(now)
	if current, ok := r.byConversation[conversationID]; ok {
		return floorGrantPayload{}, &floorDeniedPayload{
			ConversationID:  conversationID,
			Reason:          floorDeniedBusy,
			SpeakerUserID:   stringPtr(current.speakerUserID),
			SpeakerDeviceID: stringPtr(current.speakerDeviceID),
		}
	}

	tokenID, err := auth.NewToken()
	if err != nil {
		tokenID = fmt.Sprintf("floor-%d", now.UnixNano())
	}
	lease := floorLease{
		conversationID:  conversationID,
		tokenID:         tokenID,
		connectionID:    requester.connectionID,
		speakerUserID:   requester.userID,
		speakerDeviceID: requester.deviceID,
		grantedAt:       now.UTC(),
		expiresAt:       now.UTC().Add(r.ttl),
	}
	r.byConversation[conversationID] = lease
	return floorGrantPayload{
		ConversationID:  conversationID,
		TokenID:         tokenID,
		SpeakerUserID:   requester.userID,
		SpeakerDeviceID: requester.deviceID,
		GrantedAt:       lease.grantedAt,
	}, nil
}

func (r *floorRegistry) release(conversationID string, tokenID string, connectionID string, reason string) *floorReleasedPayload {
	r.mu.Lock()
	defer r.mu.Unlock()

	current, ok := r.byConversation[conversationID]
	if !ok || current.tokenID != tokenID || current.connectionID != connectionID {
		return nil
	}
	delete(r.byConversation, conversationID)
	return &floorReleasedPayload{
		ConversationID: conversationID,
		TokenID:        tokenID,
		Reason:         reason,
	}
}

func (r *floorRegistry) releaseForConnection(connectionID string, reason string) *floorReleasedPayload {
	r.mu.Lock()
	defer r.mu.Unlock()

	for conversationID, current := range r.byConversation {
		if current.connectionID != connectionID {
			continue
		}
		delete(r.byConversation, conversationID)
		return &floorReleasedPayload{
			ConversationID: conversationID,
			TokenID:        current.tokenID,
			Reason:         reason,
		}
	}
	return nil
}

func (r *floorRegistry) expire(now time.Time) []floorReleasedPayload {
	r.mu.Lock()
	defer r.mu.Unlock()

	return r.expireLocked(now)
}

func (r *floorRegistry) snapshot(conversationID string, now time.Time) floorPayload {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.expireLocked(now)
	current, ok := r.byConversation[conversationID]
	if !ok {
		return floorPayload{State: "idle"}
	}
	return floorPayload{
		State:                 "held",
		ActiveSpeakerID:       stringPtr(current.speakerUserID),
		ActiveSpeakerDeviceID: stringPtr(current.speakerDeviceID),
	}
}

func (r *floorRegistry) expireLocked(now time.Time) []floorReleasedPayload {
	var released []floorReleasedPayload
	for conversationID, current := range r.byConversation {
		if now.Before(current.expiresAt) {
			continue
		}
		delete(r.byConversation, conversationID)
		released = append(released, floorReleasedPayload{
			ConversationID: conversationID,
			TokenID:        current.tokenID,
			Reason:         floorReleasedTimeout,
		})
	}
	return released
}

func stringPtr(value string) *string {
	return &value
}
