# Beta Release Observability And QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Prepare Toki for direct private beta distribution with signing, notarization, auto-update, privacy-safe diagnostics, and an MVP QA matrix.

**Architecture:** Ship a signed and notarized Mac app outside the Mac App Store. Keep diagnostics metadata-only and privacy-safe. Treat strict P2P failures as expected observable product states, not hidden errors.

**Tech Stack:** Apple Developer ID signing, notarization, Sparkle or equivalent auto-update framework, Go service deployment, structured logging, privacy-safe crash reporting.

## Global Constraints

- Direct beta distribution first.
- No Mac App Store assumptions in MVP.
- Diagnostics must not include raw audio, replay data, SDP bodies, ICE candidate bodies, auth tokens, or email magic-link tokens.
- Release checks must verify that no server-routed media path exists.

---

## Deliverables

- Developer ID signing and notarization flow.
- Auto-update channel for beta builds.
- Backend deployment checklist.
- Privacy-safe client and backend logs.
- QA matrix for permissions, network conditions, audio devices, PTT behavior, and P2P failure states.
- Beta release acceptance checklist.

## Implementation Steps

- [x] Create release configuration for Developer ID signing.
- [x] Add notarization workflow documentation and local verification commands.
- [x] Add auto-update feed configuration for beta builds.
- [x] Add app version, build number, and update channel display in settings.
- [x] Add structured client logs for state transitions: auth, realtime, room join, floor, peer connection, permission, and device fallback.
- [x] Redact or omit sensitive fields from logs: tokens, emails where unnecessary, SDP bodies, ICE candidates, audio data, and replay buffers.
- [x] Add backend structured logs for request IDs, user IDs, team IDs, conversation IDs, event types, and failure reasons.
- [x] Add a diagnostics export that includes metadata only and requires explicit user action.
- [x] Add crash reporting only if it can be configured to exclude audio buffers and sensitive payloads. Crash reporting remains disabled until a provider is selected and verified against the privacy exclusions.
- [x] Build a QA matrix covering fresh install, permissions denied, two-user LAN call, 10-person room, simultaneous PTT, reconnect, backend restart, device unplug, and restrictive network failure.
- [x] Add a final pre-beta checklist requiring explicit confirmation that TURN and server media are disabled.

## Interfaces

- Client diagnostics export contains app version, macOS version, device model, permission states, selected device names, realtime event summaries, peer connection states, and redacted error messages.
- Backend diagnostics contain request IDs, event types, status codes, and redacted error reasons.
- Release checklist records signing identity, notarization result, update feed URL, backend version, and QA pass/fail summary.

## Acceptance Criteria

- The beta app installs on a clean Mac without Gatekeeper warnings after notarization.
- Auto-update can move a beta user from one version to the next.
- Diagnostics can explain common failures without leaking audio or secrets.
- QA explicitly verifies successful P2P and failed P2P cases.
- Release cannot be marked ready unless no TURN/media relay configuration is present.

## Verification

- Run signing and notarization validation on a clean build.
- Run update test from version N to N+1.
- Review diagnostics export manually for sensitive payloads.
- Run the full QA matrix before each beta release.
- Search config and code for TURN, relay, SFU, MCU, and media-upload paths before release.
