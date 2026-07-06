package realtime

import (
	"testing"
	"time"
)

func TestFloorRegistryGrantsDeniesReleasesAndCleansUp(t *testing.T) {
	registry := newFloorRegistry(5 * time.Minute)
	now := time.Date(2026, 7, 6, 10, 0, 0, 0, time.UTC)
	alice := floorRequester{connectionID: "connection-a", userID: "user-a", deviceID: "device-a"}
	bob := floorRequester{connectionID: "connection-b", userID: "user-b", deviceID: "device-b"}

	grant, denied := registry.request("conversation-1", alice, now)
	if denied != nil {
		t.Fatalf("first request denial = %+v, want grant", denied)
	}
	if grant.ConversationID != "conversation-1" || grant.SpeakerUserID != alice.userID || grant.SpeakerDeviceID != alice.deviceID || grant.TokenID == "" {
		t.Fatalf("grant = %+v, want alice floor token", grant)
	}

	_, denied = registry.request("conversation-1", bob, now.Add(time.Second))
	if denied == nil || denied.Reason != floorDeniedBusy || denied.SpeakerUserID == nil || *denied.SpeakerUserID != alice.userID {
		t.Fatalf("busy denial = %+v, want alice as active speaker", denied)
	}

	if released := registry.release("conversation-1", "wrong-token", alice.connectionID, floorReleasedReleased); released != nil {
		t.Fatalf("wrong token release = %+v, want nil", released)
	}

	if released := registry.release("conversation-1", grant.TokenID, bob.connectionID, floorReleasedReleased); released != nil {
		t.Fatalf("non-holder release = %+v, want nil", released)
	}

	released := registry.release("conversation-1", grant.TokenID, alice.connectionID, floorReleasedReleased)
	if released == nil || released.TokenID != grant.TokenID || released.Reason != floorReleasedReleased {
		t.Fatalf("release = %+v, want released token", released)
	}

	bobGrant, denied := registry.request("conversation-1", bob, now.Add(2*time.Second))
	if denied != nil {
		t.Fatalf("bob request denial = %+v, want grant after release", denied)
	}

	released = registry.releaseForConnection("connection-b", floorReleasedDisconnect)
	if released == nil || released.TokenID != bobGrant.TokenID || released.Reason != floorReleasedDisconnect {
		t.Fatalf("disconnect cleanup = %+v, want bob token released", released)
	}
}

func TestFloorRegistryExpiresHeldFloors(t *testing.T) {
	registry := newFloorRegistry(5 * time.Minute)
	now := time.Date(2026, 7, 6, 10, 0, 0, 0, time.UTC)
	grant, denied := registry.request("conversation-1", floorRequester{
		connectionID: "connection-a",
		userID:       "user-a",
		deviceID:     "device-a",
	}, now)
	if denied != nil {
		t.Fatalf("request denial = %+v, want grant", denied)
	}

	expired := registry.expire(now.Add(5*time.Minute + time.Nanosecond))
	if len(expired) != 1 || expired[0].TokenID != grant.TokenID || expired[0].Reason != floorReleasedTimeout {
		t.Fatalf("expired floors = %+v, want one timeout release", expired)
	}

	nextGrant, denied := registry.request("conversation-1", floorRequester{
		connectionID: "connection-b",
		userID:       "user-b",
		deviceID:     "device-b",
	}, now.Add(6*time.Minute))
	if denied != nil || nextGrant.TokenID == "" {
		t.Fatalf("request after timeout grant = %+v denial=%+v, want grant", nextGrant, denied)
	}
}
