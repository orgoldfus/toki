# Toki MVP Baseline

This document records the product decisions, system boundaries, and shared vocabulary for Toki's MVP. Later plans and implementation work should reference these invariants instead of redefining product scope.

## Product Summary

Toki is a private-team Mac push-to-talk app. Invited users can open direct or group conversations, listen to one active room, and transmit audio only while actively holding push-to-talk.

The MVP is Mac-first and native. A Go backend coordinates identity, teams, conversations, presence, WebRTC signaling, and one-speaker floor control. User audio is strict peer-to-peer WebRTC media between clients.

## Product Invariants

- Private teams first: access is invite-based, not public discovery.
- Mac-first native app: mobile apps are future work.
- Active-room listening only: a client hears only the currently selected conversation.
- Hold-to-talk only: microphone audio is transmitted only while the user holds the PTT button or global shortcut.
- One speaker at a time: the backend grants a single floor token per conversation.
- Conversation size target: group conversations support up to 10 participants in MVP.
- Local-only replay: replay is limited to at most the last 2 minutes of audio already received by the active client.
- No durable audio history: raw audio must not be stored in files, databases, object storage, logs, crash reports, diagnostics, or analytics.
- No offline replay in MVP.
- No server-carried media in MVP.
- Failed direct P2P connections must be surfaced clearly to users.

## Core User Model

- Team: a private workspace containing invited users, conversations, devices, and membership rules.
- User: an invited person who can authenticate, join conversations they belong to, listen, and request the floor.
- Direct conversation: a one-to-one conversation between two team users.
- Group conversation: a named or member-derived conversation with up to 10 participants.
- Active room: the single conversation currently joined for listening, presence, signaling, and floor control on a client.
- Participant: a user or device currently relevant to a conversation, either as a member or active room peer depending on context.
- Speaker: the participant whose device currently holds the floor token and may publish microphone audio.
- Listener: a participant receiving active-room audio who does not currently hold the floor.

## Core Realtime States

- Offline: the app has no usable network connection or cannot reach the backend.
- Signed out: no authenticated session is available.
- Connected: the app is authenticated and connected to backend coordination APIs.
- Joining room: the client is entering an active room, requesting a room snapshot, and preparing peer connections.
- Listening: the client is joined to the active room and can receive peer audio.
- Requesting floor: the user is holding PTT and the client has asked the backend for the floor.
- Speaking: the backend has granted the floor and local microphone publishing is enabled.
- Floor busy: another participant holds the floor, so the local client must not publish audio.
- Reconnecting: the realtime connection dropped and the client is reauthenticating, rejoining the active room, and renegotiating peers.
- Direct P2P unavailable: one or more required peer connections cannot be established directly, and there is no server media fallback.

## Strict P2P Policy

STUN is allowed for ICE discovery. HTTPS and WebSocket APIs are allowed for auth, metadata, presence, room membership, signaling, and floor-control coordination.

TURN, SFU, MCU, media relay, server-routed media, server audio processing, and audio upload paths are not allowed in the MVP. The backend must not receive, relay, persist, log, inspect, transcribe, or moderate raw user audio.

Because the MVP is strict P2P, some networks will fail to establish direct media. Those failures are product states, not backend fallback triggers. The app must show clear states such as direct P2P unavailable, peer disconnected, reconnecting, or room full.

## MVP Scope

The MVP includes:

- Native Mac app with main window and menu bar control surface.
- Invite-based private-team authentication.
- Direct and group conversations.
- One active room per client.
- WebSocket presence, room membership, signaling, and floor-control events.
- STUN-only WebRTC peer audio with Opus over DTLS/SRTP.
- Hold-to-talk floor control with one speaker at a time.
- Local-only replay for at most 2 minutes of active-room received audio.
- Privacy-safe diagnostics and beta release checks.

The MVP does not include:

- Mobile apps.
- Offline replay.
- Durable voice history.
- Admin console.
- Billing.
- Enterprise SSO.
- Server-routed media.
- TURN relay.
- SFU or MCU media infrastructure.
- Recording.
- Transcription.
- Moderation tooling.
- Public discovery.

## Expected MVP Scale

- Private beta teams.
- Conversations with up to 10 participants.
- One active room per client.
- One current speaker per conversation.
- Metadata persistence in PostgreSQL for teams, users, invites, conversations, memberships, devices, and sessions.
- Ephemeral realtime state for room presence, peer signaling, and floor tokens.

## Privacy Checklist

Every later feature, plan, and review must confirm:

- Raw audio is not sent to the backend.
- Raw audio is not stored durably.
- Replay audio remains memory-only and is cleared on room switch, sign-out, and app quit.
- Logs, crash reports, diagnostics, analytics, and metrics do not include raw audio, replay buffers, SDP bodies, ICE candidate bodies, auth tokens, or email magic-link tokens.
- PTT publishing is disabled unless the user is holding PTT and the client has a valid granted floor token.
- P2P failure remains visible to the user and does not silently enable TURN, relay, SFU, MCU, or server-routed media.
- Any future scope change touching audio transport, storage, recording, transcription, moderation, or relay infrastructure is explicitly approved before implementation.
