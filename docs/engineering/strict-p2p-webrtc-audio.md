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

Automated Go coverage:

- Backend `/v1/ice-config` requires a bearer session.
- Backend ICE config response is STUN-only and has `relayPolicy: "disabled"`.

CI runs both Swift and Go test suites for pull requests. Local Go verification requires Go 1.22 or newer.
