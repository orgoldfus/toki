# Beta QA Matrix

Run this matrix before each direct beta release. Record the tester, date, build number, backend version, result, and notes for every row.

| Area | Scenario | Expected Result |
| --- | --- | --- |
| Install | Fresh install on a clean Mac | App launches without Gatekeeper warning after notarization. |
| Auth | Invited email signs in | Session is created, team rooms load, and token is stored outside `UserDefaults`. |
| Auth | Non-invited email attempts sign-in | User sees a failed sign-in state without leaking invite or token details. |
| Permissions | Microphone denied | PTT is disabled and the user sees the microphone recovery state. |
| Permissions | Input monitoring denied | Keyboard shortcut is disabled, manual PTT remains available. |
| Audio devices | Selected microphone is unplugged | App falls back to the system default and shows a non-blocking warning. |
| Audio devices | Selected output is unplugged | App falls back to the system default and shows a non-blocking warning. |
| PTT | Two users on the same LAN complete a call | Only the active room is audible and the speaker transmits only while holding PTT. |
| PTT | Two users press PTT at the same time | Backend grants one floor token; the other user sees floor busy. |
| Group | 10-person room joins | Room remains capped at 10 participants and presence is visible. |
| Reconnect | Network drops and returns | Client shows reconnecting, rejoins the active room, and renegotiates peers. |
| Backend restart | Backend restarts during active room | Client requires room rejoin and peer renegotiation before transmitting. |
| Restrictive network | Direct P2P cannot be established | User sees direct P2P unavailable and Toki does not transmit. |
| Replay | Local replay after received audio | Replay plays only locally received active-room audio and clears on room switch/sign-out. |
| Diagnostics | User exports diagnostics | Export contains metadata only and no raw audio, replay data, SDP, ICE candidate bodies, tokens, or emails. |
| Update | Version N updates to N+1 | Sparkle-compatible beta feed updates the app and preserves settings. |
| Release gate | Pre-beta policy check runs | No TURN, SFU, MCU, media upload, or server media path is present. |
