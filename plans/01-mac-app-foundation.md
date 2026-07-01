# Mac App Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Build the native Mac app shell, local state model, menu bar surface, permissions flow, and global PTT input foundation.

**Architecture:** Use SwiftUI for primary screens and AppKit for menu bar, global shortcut, and desktop integration. Keep app state in a single observable session model so audio, realtime, and UI layers react to one source of truth.

**Tech Stack:** SwiftUI, AppKit, Combine or Swift Observation, Keychain, UserDefaults, AVFoundation permission APIs.

## Global Constraints

- Mac-first native app.
- The app must feel like a compact utility, not a chat clone.
- Transmit only while hold-to-talk input is active and the floor is granted.
- Permission failures must fail closed and show clear recovery actions.
- Do not implement media transport in this phase beyond interfaces and state hooks.

---

## Deliverables

- App shell with main window and menu bar item.
- Local app state model for auth, active room, realtime connection, PTT state, and permission status.
- Permission onboarding for microphone and global shortcut/input monitoring.
- Settings for selected microphone, output device placeholder, PTT shortcut, launch-at-login placeholder, and diagnostics opt-in placeholder.

## Implementation Steps

- [ ] Create the Xcode project or Swift package layout for the Mac app.
- [ ] Add `TokiApp` entry point with SwiftUI lifecycle.
- [ ] Add an AppKit menu bar controller that reflects current state: signed out, connected, listening, speaking, reconnecting, or P2P unavailable.
- [ ] Add a compact main window with three regions: conversation list, active room panel, and bottom PTT/status strip.
- [ ] Add `AppSessionState` with explicit enum-backed states instead of scattered booleans.
- [ ] Add local settings storage for selected input device ID, selected output device ID, PTT shortcut, and launch-at-login preference.
- [ ] Add microphone permission request and denied-state UI.
- [ ] Add input-monitoring/global-shortcut permission education and denied-state UI.
- [ ] Add global hold-to-talk shortcut capture with a local mock action that changes UI state only.
- [ ] Add a manual hold-to-talk button in the active room panel for mouse input.

## Interfaces

- `AppSessionState` exposes auth state, active conversation ID, realtime connection state, floor state, permission state, and device preferences.
- `PushToTalkInputController` emits `pressed` and `released` events.
- `PermissionCoordinator` exposes microphone and input-monitoring status.
- `MenuBarController` consumes `AppSessionState` and exposes quick actions: open Toki, mute output, switch active room, quit.

## Acceptance Criteria

- A signed-in mock user can open the app window, select a mock conversation, and see active room status.
- Holding the UI PTT button or global shortcut changes local state to requesting/speaking mock state; releasing returns to listening.
- If microphone permission is denied, PTT controls are disabled and the app explains how to recover.
- If input-monitoring/global-shortcut permission is unavailable, the in-window PTT button still works.
- The menu bar item always reflects the current mock state.

## Verification

- Unit test app state transitions for idle, listening, requesting floor, speaking, floor busy, reconnecting, and permission denied.
- UI smoke test the onboarding path, main window, and menu bar labels.
- Manually verify the app does not access microphone capture until the user grants permission and triggers PTT.
