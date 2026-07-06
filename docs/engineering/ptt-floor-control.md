# PTT Floor Control

This phase wires hold-to-talk intent to an ephemeral backend floor token. The backend coordinates who may speak; user audio remains strict peer-to-peer and never crosses the backend.

## Runtime Contract

- A client must be joined to the active room before sending `floor.request`.
- The request payload includes the active conversation ID and the authenticated device ID.
- The backend grants only one floor token per conversation.
- A busy floor returns `floor.denied` with reason `busy` and the current speaker identity when available.
- `floor.release` must include the current token ID and come from the socket that owns the floor.
- Floor tokens are sent to the grantee, not to listeners in `floor.changed` or room snapshot state.
- Held floors are cleared on explicit release, speaking socket disconnect, room leave, timeout, or backend restart.
- The maximum continuous hold duration is 5 minutes.

## Client Publishing Gate

The client enters requesting state on PTT press and sends `floor.request`, but microphone publishing stays disabled. Publishing is enabled only when the local user receives `floor.granted` while PTT is still held. `PeerConnectionManager.applyFloor` maps that state into peer publishing, enabling media only for a local granted floor and disabling it for requesting, busy, idle, blocked, or remote-speaker states.

Release and failure paths fail closed:

- PTT release immediately disables local publishing before sending `floor.release`.
- Denial leaves publishing disabled.
- Reconnect, P2P unavailable, disconnect, timeout, and remote release events clear publishing state.
- If the release message cannot reach the backend, local publishing remains stopped and the backend clears the stale token by disconnect cleanup or timeout.

## Realtime Events

Client events:

- `floor.request`
- `floor.release`

Server events:

- `floor.granted`
- `floor.denied`
- `floor.released`
- `floor.changed`

`floor.changed` informs listeners when another device becomes the active speaker. `floor.released` tells all joined clients why the floor cleared: `released`, `disconnect`, `timeout`, or `server_reset`.

## Testing

Automated Swift coverage verifies:

- PTT press requests floor without enabling publishing.
- Local publishing starts only after a local token grant.
- Peer publishing follows only a local granted floor.
- Release, denial, timeout, reconnect, and P2P failure states stop publishing.
- Floor request and release events encode conversation, device, and token IDs.
- Server floor grant payloads decode with token and speaker identity.

Automated Go coverage verifies:

- The floor registry grants the first requester and denies concurrent speakers.
- Wrong-token release attempts do not clear the floor.
- Explicit release allows a later requester to speak.
- Disconnect cleanup clears a held floor.
- Held floors time out after the maximum duration.
- `/v1/realtime` requires joined active-room state before floor requests and returns busy denial for competing speakers.
