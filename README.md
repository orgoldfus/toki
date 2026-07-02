# Toki

Toki is a Mac-first private-team push-to-talk app. The MVP lets invited users sign in, join one active direct or group conversation, listen only to that active room, and transmit only while holding push-to-talk.

The media policy is strict peer-to-peer for the MVP. The backend may coordinate identity, teams, conversations, presence, signaling, and floor control, but it must not receive, relay, process, or store raw user audio.

## Current Shape

- Mac client: SwiftUI/AppKit Swift package in `Sources/TokiApp` and shared client/state code in `Sources/TokiCore`.
- Backend: Go HTTP service in `cmd/toki-server` with auth/conversation handlers under `internal/httpapi`.
- Storage: PostgreSQL metadata migration in `migrations/001_metadata.sql`; current backend tests use an in-memory store.
- Auth: invited-email development magic-link flow, bearer session token, client-side Keychain token storage.
- Conversations: signed-in users can list conversations, create direct/group conversations, and add group members.

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
- `GET /v1/conversations` returns conversations visible to the signed-in user.
- `POST /v1/conversations` creates a direct or group conversation.
- `POST /v1/conversations/{id}/members` adds invited team users to a group conversation.

## Verification Notes

The current backend skeleton intentionally avoids audio paths. Re-check this before merging any future realtime, WebRTC, replay, diagnostics, or observability changes.
