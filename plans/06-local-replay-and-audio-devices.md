# Local Replay And Audio Devices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Add local-only missed replay, microphone/output device controls, level meters, and mic test behavior without introducing durable audio storage.

**Architecture:** The Mac client keeps an in-memory ring buffer of decoded or encoded audio segments received in the active room. Replay is scoped to the active room and is cleared on room switch, sign-out, and app quit.

**Tech Stack:** AVFoundation/CoreAudio device enumeration, WebRTC audio callbacks, in-memory ring buffer, SwiftUI settings.

## Global Constraints

- Replay buffer is memory-only.
- Replay is limited to the last 2 minutes.
- Replay contains only audio already received by the client.
- Replay clears on room switch, sign-out, and app quit.
- Do not write replay audio to disk, crash logs, analytics, or backend APIs.

---

## Deliverables

- Input and output device selection UI.
- Mic test and input level meter.
- Active-room output level/speaker indicator.
- In-memory replay buffer for last 2 minutes of received active-room audio.
- Replay controls for recent missed audio.

## Implementation Steps

- [x] Add device enumeration for available microphone inputs and output devices.
- [x] Persist selected device IDs in local settings.
- [x] If a selected device disappears, fall back to system default and show a non-blocking warning.
- [x] Add microphone test mode that captures local mic level without sending audio to peers.
- [x] Add input level meter that works during mic test and while speaking.
- [x] Add output level indicator for the active remote speaker.
- [x] Create `LocalReplayBuffer` with fixed 2-minute capacity and no disk persistence.
- [x] Append received active-room audio segments to the replay buffer.
- [x] Do not append local microphone audio before it returns as a received remote stream.
- [x] Clear the replay buffer on active room switch.
- [x] Clear the replay buffer on sign-out and app termination.
- [x] Add replay UI showing available recent audio duration and a play button.
- [x] During replay playback, do not transmit and do not change floor state.

## Completion Notes

- Implemented as Swift client/core seams in `AudioDeviceManager`, `MicrophoneTestController`, `LocalReplayBuffer`, `ReplayPlayer`, and `AppSessionState`.
- The native WebRTC dependency is still pending, so real received-audio callbacks should feed `AppSessionState.appendReceivedAudio(_:conversationID:)` when the media layer lands.
- CI already runs `swift build` and `swift test`, which cover the new Swift unit and app-shell tests.

## Interfaces

- `AudioDeviceManager` lists devices, stores selected IDs, and reports fallback state.
- `MicrophoneTestController` exposes input level without network publishing.
- `LocalReplayBuffer.append(segment, speakerId, receivedAt)` stores active-room received audio in memory.
- `LocalReplayBuffer.clear(reason)` clears memory on room switch, sign-out, or quit.
- `ReplayPlayer.playRecent(duration)` plays buffered audio locally only.

## Acceptance Criteria

- Users can select input and output devices.
- Mic test produces level feedback but sends no audio.
- Replay offers at most 2 minutes of active-room received audio.
- Replay is unavailable after switching rooms or restarting the app.
- No replay data exists on disk.
- Replay playback does not request the floor or publish audio.

## Verification

- Unit tests for ring-buffer capacity, trimming, clearing, and no-disk persistence.
- Unit tests for room-switch and sign-out clearing.
- Manual test with two users: receive audio, replay it locally, switch rooms, confirm replay is gone.
- Manual test unplugging the selected microphone and output device.
- Search the codebase for file writes in replay code and confirm none exist.
