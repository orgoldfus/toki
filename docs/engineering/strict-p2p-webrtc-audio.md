# Strict P2P WebRTC Audio

This phase establishes the enforceable strict-P2P contracts before native media wiring.

## Implemented Contracts

- `GET /v1/ice-config` is authenticated and returns only STUN URLs with `relayPolicy: "disabled"`.
- Swift client code validates ICE config before use.
- TURN URLs, relay policy changes, and relay ICE candidates are rejected client-side.
- `PeerConnectionManager` builds an active-room peer mesh from `room.snapshot`.
- Device IDs choose the initial offerer deterministically: the lexicographically smaller device ID offers.
- Offers, answers, and ICE candidates are sent through the existing realtime signaling envelope.
- Leaving or switching rooms closes all tracked peer connections and disables publishing.
- PTT floor control gates microphone publishing on a valid local floor token; see [`ptt-floor-control.md`](ptt-floor-control.md).

## Not Yet Implemented

- Native WebRTC library integration.
- Real microphone capture and Opus track publishing.
- Remote audio track playback through selected output devices.
- User-facing per-peer diagnostics beyond the existing P2P failure state model.
- Manual two-client LAN and restrictive-network verification.

## Testing

Automated Swift coverage:

- ICE config validation accepts STUN-only config.
- ICE config validation rejects TURN URLs, enabled relay policy, and relay candidates.
- API client fetches `/v1/ice-config` with bearer auth and validates the response.
- Room snapshots decode the backend JSON keys.
- Peer manager creates per-peer connections, selects the deterministic offerer, sends signaling envelopes, and closes connections on room leave.
- Floor-control state keeps publishing disabled until a local grant and clears it on release, denial, timeout, reconnect, and P2P failure.

Automated Go coverage:

- Backend `/v1/ice-config` requires a bearer session.
- Backend ICE config response is STUN-only and has `relayPolicy: "disabled"`.
- Backend realtime floor control grants one speaker, denies busy requests, releases by token, clears on disconnect, and times out held floors.

CI runs both Swift and Go test suites for pull requests. Local Go verification requires Go 1.22 or newer.
