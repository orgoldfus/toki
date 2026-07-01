# Product And Architecture Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the immutable MVP product decisions, system boundaries, and shared vocabulary for Toki.

**Architecture:** Toki is a native Mac app backed by a Go coordination service. Audio is strict peer-to-peer WebRTC media; the backend only manages auth, teams, conversations, presence, signaling, and one-speaker floor control.

**Tech Stack:** SwiftUI, AppKit, WebRTC native client, Go, PostgreSQL, WebSocket, STUN-only ICE.

## Global Constraints

- Build for private teams first.
- Mac-first native app; mobile apps are future work.
- Active-room listening only.
- Hold-to-talk only.
- One speaker at a time.
- Groups support up to 10 participants in MVP.
- Local-only replay buffer is limited to 2 minutes.
- Backend must not receive, relay, persist, log, or inspect user audio.
- TURN, SFU, MCU, and server-routed media are out of scope for MVP.

---

## Deliverables

- A repository-level product decision record.
- A shared glossary used by client and backend plans.
- A concise MVP scope boundary to prevent accidental expansion.
- A privacy and networking policy that future implementation tasks must preserve.

## Implementation Steps

- [x] Create `docs/product/mvp-baseline.md` with the product invariants from this plan.
- [x] Define the core user model: team, user, direct conversation, group conversation, active room, participant, speaker, listener.
- [x] Define the core realtime states: offline, signed out, connected, joining room, listening, requesting floor, speaking, floor busy, reconnecting, direct P2P unavailable.
- [x] Define the strict P2P policy: STUN is allowed for discovery; signaling is allowed for coordination; TURN and media relay are not allowed in MVP.
- [x] Define the MVP non-goals: mobile apps, offline replay, durable voice history, admin console, billing, enterprise SSO, server-routed media, moderation tooling, and public discovery.
- [x] Record the expected MVP scale: private beta teams, conversations up to 10 participants, one active room per client.
- [x] Add a privacy checklist requiring every later feature to confirm that raw audio is not stored or sent to the backend.

## Acceptance Criteria

- The baseline document can be read alone and answer what the MVP is, what it is not, and what must never change accidentally.
- Every later implementation plan references these invariants rather than redefining product scope.
- Any engineer can explain why strict P2P causes visible connection-failure states instead of server fallback.

## Verification

- Review the baseline for contradictions with the other plan files.
- Search for forbidden terms in future implementation proposals: `TURN`, `SFU`, `MCU`, `recording`, `transcription`, `server audio`, `audio upload`.
- Confirm any appearance of those terms is either explicitly marked out of scope or covered by a future approved scope change.
