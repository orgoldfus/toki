# Toki

Toki is a Mac-first private-team push-to-talk app. The MVP lets invited users sign in, join one active direct or group conversation, listen only to that active room, and transmit only while holding push-to-talk.

The media policy is strict peer-to-peer for the MVP. The backend may coordinate identity, teams, conversations, presence, signaling, and floor control, but it must not receive, relay, process, or store raw user audio.

## Current Shape

- Mac client: SwiftUI/AppKit Swift package in `Sources/TokiApp` and shared client/state code in `Sources/TokiCore`.
- Backend: Go HTTP service in `cmd/toki-server` with auth/conversation handlers under `internal/httpapi`.
- Storage: PostgreSQL metadata migration in `migrations/001_metadata.sql`; current backend tests use an in-memory store.
- Auth: invited-email development magic-link flow, bearer session token, client-side Keychain token storage.
- Conversations: signed-in users can list conversations, create direct/group conversations, and add group members.
- Realtime: authenticated `/v1/realtime` WebSocket for active-room presence and WebRTC signaling metadata.
- Strict P2P media foundation: authenticated STUN-only ICE config, client-side TURN/relay rejection, and a protocol-backed peer connection manager for active-room mesh setup.

## Product Constraints

- Private teams only; no public discovery.
- Active-room listening only.
- Hold-to-talk only.
- One speaker at a time.
- Groups are designed around up to 10 participants.
- Session tokens must not be stored in `UserDefaults` or logs.
- Backend persistence is metadata-only. Do not add raw audio storage, TURN, SFU, MCU, or server-routed media for the MVP.

## Requirements

- macOS 14 or newer for the Swift package targets.
- Xcode with Swift 5.10 support.
- Go 1.22 or newer for backend work.
- PostgreSQL for durable backend development once the store is connected to the migration-backed database.

## Development

All shell commands in this project should be prefixed with `rtk`.

Run the Swift test suite:

```bash
rtk swift test
```

Run the backend test suite when Go is installed:

```bash
rtk go test ./...
```

Run the realtime-focused Swift tests:

```bash
rtk swift test --filter RealtimeConnectionManagerTests
```

Run the development backend with in-memory storage and invited beta emails:

```bash
TOKI_DEV_INVITES=alice@example.com,bob@example.com rtk go run ./cmd/toki-server
```

Run the backend with PostgreSQL metadata storage:

```bash
TOKI_DATABASE_URL=postgres://user:password@127.0.0.1:5432/toki?sslmode=disable TOKI_DEV_INVITES=alice@example.com rtk go run ./cmd/toki-server
```

When `TOKI_DATABASE_URL` is set, the server applies `migrations/001_metadata.sql` before seeding development invites.

Run the store contract against PostgreSQL:

```bash
TOKI_TEST_DATABASE_URL=postgres://user:password@127.0.0.1:5432/toki_test?sslmode=disable rtk go test ./internal/store
```

The Mac app expects the local backend at `http://127.0.0.1:8080` by default.

## API Overview

- `POST /v1/auth/magic-link` with `{ "email": "user@example.com" }` returns a development magic-link token for invited emails.
- `POST /v1/auth/session` with `{ "token": "opaque-token", "deviceName": "Alice's MacBook Pro" }` returns a bearer session token, user, membership, and device.
- `GET /v1/me` returns the current user, team memberships, and registered devices.
- `GET /v1/ice-config` returns STUN-only ICE servers and `{ "relayPolicy": "disabled" }`.
- `GET /v1/conversations` returns conversations visible to the signed-in user.
- `POST /v1/conversations` creates a direct or group conversation.
- `POST /v1/conversations/{id}/members` adds invited team users to a group conversation.
- `GET /v1/realtime` upgrades to an authenticated WebSocket when the request includes the bearer session token.

## Realtime Protocol

Realtime messages use a JSON envelope:

```json
{
  "type": "room.join",
  "id": "client-event-id",
  "conversationId": "conversation_1",
  "sentAt": "2026-07-05T10:00:00Z",
  "payload": {}
}
```

Client event types are `room.join`, `room.leave`, `presence.set`, `signal.offer`, `signal.answer`, and `signal.iceCandidate`.

Server event types are `room.snapshot`, `presence.updated`, `signal.forwarded`, `error`, and `reconnect.required`.

The WebSocket carries presence, room membership, and WebRTC signaling bodies only. It must not carry raw audio frames. Signaling is forwarded only between devices currently joined to the same authorized conversation. The client rejects ICE configs with TURN URLs, non-disabled relay policy, or relay ICE candidates.

## Strict P2P WebRTC Status

Implemented in the current foundation:

- Backend `GET /v1/ice-config` requires a bearer session and returns STUN-only ICE config.
- `TokiAPIClient.iceConfig(sessionToken:)` validates the response before returning it to app code.
- `StrictP2PICEPolicy` rejects TURN URLs, relay policy changes, and relay ICE candidates.
- `PeerConnectionManager` creates peer connections from `room.snapshot`, uses lexicographic device IDs for deterministic offerer selection, forwards offer/answer/candidate signaling over the realtime transport, and closes all peer connections when leaving or switching rooms.

Still intentionally pending until the native WebRTC dependency is selected and wired:

- Real native WebRTC peer connection creation.
- Microphone track attachment from the floor-controlled PTT flow.
- Remote audio playback through selected output devices.
- Manual two-client LAN and restrictive-network media tests.

## Verification Notes

The backend realtime channel intentionally avoids audio paths. Re-check this before merging any future WebRTC, replay, diagnostics, or observability changes.

CI runs the full Swift package tests and Go backend tests on pull requests. The phase-04 automated coverage includes strict ICE validation, authenticated ICE config fetching, peer mesh lifecycle/signaling behavior, and the backend ICE config endpoint. Local Go verification requires Go 1.22 or newer to be installed.
