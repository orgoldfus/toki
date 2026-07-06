# Toki

Toki is a Mac-first private-team push-to-talk app. The MVP lets invited users sign in, join one active direct or group conversation, listen only to that active room, and transmit only while holding push-to-talk.

The media policy is strict peer-to-peer for the MVP. The backend may coordinate identity, teams, conversations, presence, signaling, and floor control, but it must not receive, relay, process, or store raw user audio.

## Current Shape

- Mac client: SwiftUI/AppKit Swift package in `Sources/TokiApp` and shared client/state code in `Sources/TokiCore`.
- Backend: Go HTTP service in `cmd/toki-server` with auth/conversation handlers under `internal/httpapi`.
- Storage: PostgreSQL metadata migration in `migrations/001_metadata.sql`; current backend tests use an in-memory store.
- Auth: invited-email development magic-link flow, bearer session token, client-side Keychain token storage.
- Conversations: signed-in users can list conversations, create direct/group conversations, and add group members.
- Realtime: authenticated `/v1/realtime` WebSocket for active-room presence, WebRTC signaling metadata, and one-speaker floor control.
- PTT floor control: backend grants one ephemeral floor token per conversation, denies concurrent speakers, and clears held floors on release, disconnect, timeout, or backend restart.
- Strict P2P media foundation: authenticated STUN-only ICE config, client-side TURN/relay rejection, and a protocol-backed peer connection manager for active-room mesh setup.
- Local audio controls: dynamic microphone/output device selection, mic test/input level state, active-speaker output level state, and local-only replay state capped at 2 minutes.

## Product Constraints

- Private teams only; no public discovery.
- Active-room listening only.
- Hold-to-talk only.
- One speaker at a time.
- Groups are designed around up to 10 participants.
- Replay is local-only, memory-only, scoped to the active room, and capped at the last 2 minutes of received audio.
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

Client event types are `room.join`, `room.leave`, `presence.set`, `signal.offer`, `signal.answer`, `signal.iceCandidate`, `floor.request`, and `floor.release`.

Server event types are `room.snapshot`, `presence.updated`, `signal.forwarded`, `floor.granted`, `floor.denied`, `floor.released`, `floor.changed`, `error`, and `reconnect.required`.

Floor-control payloads:

- `floor.request`: `{ "conversationId": "...", "deviceId": "..." }`
- `floor.granted`: `{ "conversationId": "...", "tokenId": "...", "speakerUserId": "...", "speakerDeviceId": "...", "grantedAt": "..." }`
- `floor.denied`: `{ "conversationId": "...", "reason": "busy" }`
- `floor.release`: `{ "conversationId": "...", "tokenId": "..." }`
- `floor.released`: `{ "conversationId": "...", "tokenId": "...", "reason": "released|disconnect|timeout|server_reset" }`

The WebSocket carries presence, room membership, and WebRTC signaling bodies only. It must not carry raw audio frames. Signaling is forwarded only between devices currently joined to the same authorized conversation. The client rejects ICE configs with TURN URLs, non-disabled relay policy, or relay ICE candidates.

PTT press requests the floor but does not enable microphone publishing. Publishing is allowed only after `floor.granted` gives the local user a token, and release/reconnect/timeout paths stop local publishing before or regardless of whether the backend receives the release.

## Strict P2P WebRTC Status

Implemented in the current foundation:

- Backend `GET /v1/ice-config` requires a bearer session and returns STUN-only ICE config.
- `TokiAPIClient.iceConfig(sessionToken:)` validates the response before returning it to app code.
- `StrictP2PICEPolicy` rejects TURN URLs, relay policy changes, and relay ICE candidates.
- `PeerConnectionManager` creates peer connections from `room.snapshot`, uses lexicographic device IDs for deterministic offerer selection, forwards offer/answer/candidate signaling over the realtime transport, and closes all peer connections when leaving or switching rooms.
- `AppSessionState` gates local microphone publishing on a valid local floor token, and `PeerConnectionManager.applyFloor` enables peer publishing only for a local grant.

Still intentionally pending until the native WebRTC dependency is selected and wired:

- Real native WebRTC peer connection creation.
- Microphone track attachment from the floor-controlled PTT flow.
- Remote audio playback through selected output devices.
- Feeding real received WebRTC audio callbacks into the local replay buffer.
- Manual two-client LAN and restrictive-network media tests.

## Local Replay And Audio Devices

Implemented in the current client foundation:

- `AudioDeviceManager` enumerates microphone inputs and output devices, persists selected device IDs, and falls back to system defaults with a non-blocking warning when a selected device disappears.
- `MicrophoneTestController` exposes local input level for mic test and speaking-state UI without enabling microphone publishing.
- `LocalReplayBuffer` keeps a process-local 120-second buffer of received active-room audio segments only.
- Replay clears on active room switch, sign-out, and app termination.
- `ReplayPlayer` plays recent local segments without requesting the floor or publishing microphone audio.
- The app shell and settings UI expose device selection, mic test level, active output level, and replay duration/play controls.

The replay buffer is not persisted to disk, `UserDefaults`, backend APIs, logs, crash reports, analytics, or diagnostics. See [`docs/engineering/local-replay-and-audio-devices.md`](docs/engineering/local-replay-and-audio-devices.md) for the implementation contract.

## Verification Notes

The backend realtime channel intentionally avoids audio paths. Re-check this before merging any future WebRTC, replay, diagnostics, or observability changes.

CI runs the full Swift package tests and Go backend tests on pull requests. The current automated coverage includes strict ICE validation, authenticated ICE config fetching, peer mesh lifecycle/signaling behavior, token-aware PTT floor state, realtime floor request/release encoding, local replay capacity/clearing/privacy behavior, audio device selection/fallback behavior, mic-test level behavior, app-shell replay controls, backend floor grant/deny/release/disconnect/timeout behavior, and the backend ICE config endpoint. Local Go verification requires Go 1.22 or newer to be installed.
