# Strict P2P WebRTC Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Implement direct peer-to-peer WebRTC audio for the active room without TURN, SFU, MCU, or server-routed media.

**Architecture:** Each active room uses a peer-connection mesh between joined devices. The current speaker publishes microphone audio to every connected peer; listeners receive and play remote audio streams directly from peers.

**Tech Stack:** WebRTC native library, Opus, ICE/STUN, DTLS/SRTP, Swift audio integration, WebSocket signaling from plan 03.

## Global Constraints

- STUN-only ICE config.
- TURN relay is forbidden in MVP.
- The backend must not carry audio media.
- If direct peer connectivity fails, the app must show a clear P2P failure state.
- Support up to 10 participants in one conversation.

---

## Deliverables

- WebRTC client wrapper with peer lifecycle management.
- STUN-only ICE config endpoint and client integration.
- Peer mesh setup for active room participants.
- Remote audio playback from connected peers.
- P2P connection failure UI and diagnostics.

## Implementation Steps

- [ ] Add `GET /v1/ice-config` returning only STUN server URLs and an explicit `relayPolicy: "disabled"` field.
- [ ] Add a client assertion that rejects ICE config containing TURN URLs or relay candidates.
- [ ] Create `PeerConnectionManager` responsible for creating, tracking, and closing peer connections per active conversation.
- [ ] On `room.snapshot`, create peer connections for all currently joined peers.
- [ ] Use deterministic offerer selection to avoid glare: the lexicographically smaller device ID creates the initial offer.
- [ ] Forward offers, answers, and ICE candidates through the WebSocket signaling channel.
- [ ] Attach microphone audio track only when local PTT flow grants speaking permission in plan 05.
- [ ] Receive remote audio tracks and route them to the selected output device.
- [ ] Monitor ICE states and expose connecting, connected, disconnected, failed, and closed states.
- [ ] If a required peer reaches failed state, show "Direct peer connection unavailable on this network" for that peer and conversation.
- [ ] Close all peer connections when switching active rooms.

## Interfaces

- Backend REST `GET /v1/ice-config`: returns `{ "iceServers": [{ "urls": ["stun:..."] }], "relayPolicy": "disabled" }`.
- Client `PeerConnectionManager.joinRoom(snapshot)` creates and negotiates peers.
- Client `PeerConnectionManager.leaveRoom()` closes all active peer connections.
- Client `PeerConnectionManager.setPublishingEnabled(enabled)` attaches or detaches local microphone track based on PTT state.

## Acceptance Criteria

- Two clients on a normal network establish direct audio without server media.
- The client refuses to use TURN or relay ICE candidates.
- Switching rooms closes old peer connections and stops old audio.
- A failed direct connection is visible and does not trigger hidden fallback.
- No backend endpoint accepts audio uploads or media frames.

## Verification

- Unit test ICE config validation rejects TURN URLs and relay policy changes.
- Integration test signaling negotiation with fake peer IDs.
- Manual test two Macs or two local clients on the same LAN.
- Manual failure test on a restrictive network or with blocked UDP to verify user-facing P2P failure state.
- Inspect backend request logs and WebSocket handlers to confirm no raw audio path exists.

## Implementation Status

Completed in `codex-strict-p2p-webrtc-audio-foundation`:

- Authenticated `GET /v1/ice-config` returning STUN-only URLs and `relayPolicy: "disabled"`.
- Swift strict ICE policy validation for TURN URLs, relay policy changes, and relay candidates.
- Client API integration for fetching and validating ICE config.
- Protocol-backed `PeerConnectionManager` for active-room peer tracking, deterministic offer selection, signaling envelope forwarding, publishing toggles, and room cleanup.
- Automated Swift tests for strict ICE validation, client fetch/validation, room snapshot decoding, peer mesh setup, signaling, and cleanup.
- Automated Go test coverage for the backend ICE config endpoint.

Remaining for the next implementation pass:

- Select and integrate the native WebRTC dependency.
- Create real peer connections from `PeerConnectionManager`.
- Attach microphone tracks only from the floor-controlled PTT flow.
- Receive remote audio tracks and route them to selected output devices.
- Complete two-client LAN and restrictive-network manual verification.
