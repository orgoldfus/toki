# Toki Agent Instructions

## Project Identity

Toki is a private-team Mac push-to-talk app. It lets invited users open a direct conversation or group conversation, listen to one active room, and transmit audio only while actively holding push-to-talk.

The MVP is Mac-first and native. The media path is strict peer-to-peer: servers may coordinate identity, membership, presence, signaling, and floor control, but must not carry user audio in the MVP.

## Product Invariants

- Active room only: a user hears only the currently selected conversation.
- Hold-to-talk only: audio is transmitted only while the user holds the PTT button or global shortcut.
- One speaker at a time: the backend grants a single floor token per conversation.
- Group size target: design the MVP around conversations with up to 10 participants.
- Replay is local-only: keep at most the last 2 minutes of audio already received by the active client.
- No durable audio history: do not store raw audio in files, databases, object storage, logs, crash reports, or analytics.
- No offline replay in MVP.
- No server-carried media in MVP.
- Failed direct P2P connections must be surfaced clearly to users.

## Technical Defaults

- Mac client: SwiftUI with AppKit where native desktop integration requires it.
- Menu bar: provide a compact menu bar status/control surface plus a main app window.
- Backend: Go service with HTTPS and WebSocket APIs.
- Database: PostgreSQL for durable team, user, invite, conversation, membership, device, and session data.
- Realtime: WebSocket for presence, room membership, signaling, and floor-control events.
- Media: WebRTC peer connections with Opus audio, DTLS/SRTP, and STUN-only ICE discovery.
- P2P policy: do not configure TURN or media relay for the MVP.
- Distribution: signed and notarized direct beta with auto-update support.

## Code Quality

- Follow language best practices for Swift, Go, SQL, and any supporting tooling.
- Follow DRY: extract shared logic when duplication carries real maintenance cost.
- Follow KISS: prefer straightforward, readable code over clever or over-engineered designs.
- Avoid AI slop: no redundant comments, no boilerplate doc comments that restate signatures, no filler text.
- Comments should explain why something exists, not what the next line does.
- Keep files focused. Split by responsibility when a file stops having one clear job.
- Prefer explicit state machines for realtime/audio states over scattered boolean flags.
- Keep privacy-sensitive behavior visible in code and product copy.

## Development Workflow

- Prefix shell commands with `rtk`.
- Prefer focused implementation plans and small reviewable changes.
- Write tests for behavior that changes state, permissions, realtime protocol handling, audio lifecycle, or privacy guarantees.
- Verify behavior before marking work complete.
- Do not silently weaken product invariants to make implementation easier.
- Do not add durable audio storage, TURN relay, SFU, MCU, or server-side media processing unless a future plan explicitly changes the MVP policy.

## Failure Handling Principles

- Network failure should produce actionable user states: reconnecting, direct P2P unavailable, peer disconnected, room full, or floor busy.
- Permission failure should identify the missing permission and the next action: microphone access, global shortcut/input monitoring, or audio device access.
- Privacy-sensitive failures must fail closed. If the app is not sure it has the floor or a direct peer connection, it must not transmit.
- Backend restart should require clients to rejoin active rooms and renegotiate peer connections.

