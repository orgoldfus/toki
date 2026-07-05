# Realtime Signaling And Presence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Add the realtime coordination channel for active-room membership, presence, WebRTC signaling, reconnects, and room snapshots.

**Architecture:** The Go backend exposes one authenticated WebSocket endpoint. It keeps ephemeral in-memory room state for connected devices and forwards signaling messages between authorized room peers.

**Tech Stack:** Go WebSocket library, PostgreSQL auth lookup, JSON event envelopes, Swift WebSocket client.

## Global Constraints

- WebSocket carries metadata and WebRTC signaling only.
- WebSocket must never carry raw audio frames.
- Users may join only conversations where they are members.
- Backend restart may drop ephemeral state; clients must rejoin rooms.

---

## Deliverables

- Authenticated `/v1/realtime` WebSocket endpoint.
- Event envelope shared by backend and client.
- Room join/leave and presence updates.
- WebRTC offer/answer/ICE forwarding.
- Reconnect and resync behavior for clients.

## Implementation Steps

- [x] Define a versioned JSON event envelope with `type`, `id`, `conversationId`, `sentAt`, and `payload`.
- [x] Implement WebSocket authentication using the existing session token.
- [x] Add server-side room registry keyed by conversation ID and device connection ID.
- [x] Implement `room.join` with membership authorization.
- [x] Implement `room.leave` and cleanup on socket close.
- [x] Broadcast `room.snapshot` after join with current peers, presence, and floor state placeholder.
- [x] Broadcast `presence.updated` when a device joins, leaves, reconnects, or changes active status.
- [x] Implement `signal.offer`, `signal.answer`, and `signal.iceCandidate` forwarding only between members currently joined to the same conversation.
- [x] Add client realtime connection manager with exponential backoff and explicit reconnecting state.
- [x] On reconnect, reauthenticate, rejoin the active room, request a fresh snapshot, and trigger peer renegotiation.

## Interfaces

- WebSocket endpoint: `GET /v1/realtime`.
- Client event types: `room.join`, `room.leave`, `presence.set`, `signal.offer`, `signal.answer`, `signal.iceCandidate`.
- Server event types: `room.snapshot`, `presence.updated`, `signal.forwarded`, `error`, `reconnect.required`.
- Signaling payloads include sender device ID, target device ID, SDP or ICE candidate body, and conversation ID.

## Acceptance Criteria

- A signed-in device can join exactly one active room.
- Two clients in the same conversation receive each other's presence.
- Signaling messages are forwarded only to the addressed peer.
- Unauthorized room joins and cross-room signaling are rejected.
- Backend restart causes clients to show reconnecting and then rejoin the active room.
- WebSocket logs include event type and IDs but never audio payloads or SDP bodies in production logs.

## Verification

- Backend tests for WebSocket auth, room authorization, join/leave cleanup, and signaling authorization.
- Client tests for reconnect state transitions and room rejoin behavior.
- Manual test with two local clients: join a room, exchange fake signaling messages, kill backend, restart, and confirm both clients resync.
