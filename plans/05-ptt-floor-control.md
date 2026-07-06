# PTT Floor Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Implement hold-to-talk behavior and one-speaker floor control across all participants in an active conversation.

**Architecture:** The client emits floor request/release events on PTT press/release. The backend grants one ephemeral floor token per conversation and broadcasts floor state to all joined clients.

**Tech Stack:** Swift input controller, WebSocket events, Go in-memory floor registry, monotonic server timestamps.

## Global Constraints

- Hold-to-talk only.
- One speaker at a time.
- If the client does not have a valid granted floor token, it must not publish microphone audio.
- Floor state is ephemeral and cleared on disconnect, release, timeout, or backend restart.

---

## Deliverables

- Backend floor-token registry per conversation.
- WebSocket events for floor request, grant, denial, release, timeout, and forced cleanup.
- Client state machine that gates microphone publishing on floor grant.
- UI states for speaking, floor busy, requesting floor, and speaker identity.

## Implementation Steps

- [x] Define floor event payloads with conversation ID, user ID, device ID, token ID, and server timestamp.
- [x] Implement `floor.request` handling with membership and active-room validation.
- [x] Grant the floor only if the conversation has no current speaker.
- [x] Deny the floor with reason `busy` when another device holds it.
- [x] Broadcast `floor.granted` to requester and `presence.updated` or `floor.changed` to listeners.
- [x] Implement `floor.release` requiring the current token ID.
- [x] Release the floor automatically when the speaking socket disconnects.
- [x] Add a maximum continuous hold duration for safety, such as 5 minutes, then release with reason `timeout`.
- [x] On client PTT press, enter requesting state and send `floor.request`.
- [x] Only after `floor.granted`, call `PeerConnectionManager.setPublishingEnabled(true)`.
- [x] On PTT release, immediately stop publishing locally and send `floor.release`.
- [x] If release cannot reach the backend, keep local publishing stopped and let server timeout or disconnect cleanup clear remote state.
- [x] Show the active speaker in the active room and menu bar while floor is held.

## Interfaces

- Client event `floor.request`: `{ "conversationId": "...", "deviceId": "..." }`.
- Server event `floor.granted`: `{ "conversationId": "...", "tokenId": "...", "speakerUserId": "...", "speakerDeviceId": "...", "grantedAt": "..." }`.
- Server event `floor.denied`: `{ "conversationId": "...", "reason": "busy" }`.
- Client event `floor.release`: `{ "conversationId": "...", "tokenId": "..." }`.
- Server event `floor.released`: `{ "conversationId": "...", "tokenId": "...", "reason": "released|disconnect|timeout|server_reset" }`.

## Acceptance Criteria

- Pressing PTT requests the floor but does not transmit before grant.
- If the floor is free, the requester becomes speaker and peers hear audio.
- If another speaker holds the floor, requester sees busy and no audio is transmitted.
- Releasing PTT stops local publishing immediately.
- Disconnecting while speaking clears the floor for others.
- Backend restart clears floor state; clients rejoin and return to listening.

## Verification

- Backend unit tests for floor grant, denial, release, disconnect cleanup, timeout, and unauthorized requests.
- Client state-machine tests for press, grant, release, denial, disconnect, and timeout.
- Manual two-client test: both press simultaneously and verify exactly one speaker wins.
- Manual privacy test: hold PTT without floor grant and confirm no local media publishing starts.
