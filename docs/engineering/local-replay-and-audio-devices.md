# Local Replay And Audio Devices

This phase adds the client-side state and UI seams for local-only replay, audio device selection, mic testing, and level indicators. It does not add durable audio storage or any backend audio path.

## Runtime Contract

- Replay is held in `LocalReplayBuffer`, an in-memory ring buffer capped at 120 seconds.
- The buffer stores only received active-room audio segments supplied through `AppSessionState.appendReceivedAudio`.
- Local microphone samples are not eligible for replay unless they later arrive through the received-audio path.
- Selecting a different active room clears replay immediately.
- Sign-out and app termination clear replay immediately.
- `ReplayPlayer.playRecent` returns local playback segments without requesting the floor or publishing microphone audio.

## Device And Meter Controls

- `AudioDeviceManager` enumerates available input and output devices through an `AudioDeviceProviding` interface.
- Selected input and output IDs persist through `DevicePreferences` in `LocalSettingsStore`.
- If a selected device disappears, the manager falls back to the system default and exposes a non-blocking warning for the UI.
- `MicrophoneTestController` reports input level during mic test without enabling peer publishing.
- The app shell exposes separate input and active-output level values so the UI can show mic test/speaking feedback and active remote-speaker output.

## Privacy Boundary

Replay data must stay process-local. The replay implementation does not use files, databases, `UserDefaults`, backend APIs, logs, crash reporting, analytics, or diagnostics. `DevicePreferences` may persist device IDs and non-audio settings only.

## Current Integration Point

Native WebRTC audio callbacks are still pending until the real media dependency is selected and wired. When that dependency lands, decoded or encoded remote audio received for the active room should call `AppSessionState.appendReceivedAudio(_:conversationID:)`; local capture paths must not write into `LocalReplayBuffer`.

## Testing

Automated Swift coverage verifies:

- Device enumeration, device selection persistence, and fallback warnings.
- Mic test/input-level behavior without microphone publishing.
- Replay trimming to the latest 120 seconds.
- Replay clearing on room switch, sign-out, and app termination.
- Replay playback preserving floor and publishing state.
- App-shell settings/replay state exposed to SwiftUI.
