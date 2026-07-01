# Auth Teams And Conversations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Baseline:** Preserve the product invariants in [`docs/product/mvp-baseline.md`](../docs/product/mvp-baseline.md).

**Goal:** Implement invite-based private-team identity, sessions, conversation membership, and the initial backend persistence model.

**Architecture:** The Go backend owns durable account and conversation data in PostgreSQL. The Mac client authenticates with an email magic-link flow, stores its session token in Keychain, and fetches conversations after sign-in.

**Tech Stack:** Go, PostgreSQL, SQL migrations, HTTPS REST API, secure cookies or bearer tokens, Swift client API layer, Keychain.

## Global Constraints

- Private teams only.
- Email invite auth for MVP.
- No public discovery.
- No SSO or admin console in MVP.
- Backend persists metadata only; it never stores audio.

---

## Deliverables

- Database schema for teams, users, memberships, invitations, sessions, devices, conversations, and conversation members.
- REST endpoints for magic-link auth, current user, teams, conversations, and members.
- Client sign-in and conversation list UI wired to the backend.
- Basic seed/dev mode for local private beta testing.

## Implementation Steps

- [ ] Create backend module layout: `cmd/toki-server`, `internal/httpapi`, `internal/auth`, `internal/store`, `internal/realtime`, `migrations`.
- [ ] Add PostgreSQL migrations for durable metadata tables.
- [ ] Implement invitation creation for a known team in development mode.
- [ ] Implement `POST /v1/auth/magic-link` to accept an invited email and issue a development magic-link token.
- [ ] Implement `POST /v1/auth/session` to exchange the token for a session.
- [ ] Implement session storage and revocation in PostgreSQL.
- [ ] Implement `GET /v1/me` returning user, team memberships, and devices.
- [ ] Implement `GET /v1/conversations` returning direct and group conversations for the signed-in user.
- [ ] Implement `POST /v1/conversations` for direct or group creation from invited team members.
- [ ] Implement `POST /v1/conversations/{id}/members` for adding invited users to a group conversation.
- [ ] Add Mac client API types matching the REST responses.
- [ ] Store the session token in Keychain and clear it on sign-out.
- [ ] Replace mock conversations with backend conversations.

## Interfaces

- REST `POST /v1/auth/magic-link`: request `{ "email": "user@example.com" }`.
- REST `POST /v1/auth/session`: request `{ "token": "opaque-token", "deviceName": "Alice's MacBook Pro" }`.
- REST `GET /v1/me`: returns current user, team memberships, and registered device.
- REST `GET /v1/conversations`: returns conversation ID, type, display name, members, and last presence summary.
- REST `POST /v1/conversations`: accepts `type`, `memberIds`, and optional `displayName`.

## Acceptance Criteria

- Only invited emails can create a session.
- A signed-in user sees only conversations where they are a member.
- A user cannot add non-team users to a conversation.
- Direct conversations deduplicate the same two users.
- Group conversations support up to 10 participants.
- Session token is never stored in UserDefaults or logs.

## Verification

- Backend integration tests for invite, sign-in, session lookup, conversation creation, and membership authorization.
- Client unit tests for auth API decoding and Keychain token storage.
- Manual test: sign in as two users, create a direct conversation, create a group, sign out, sign back in, and confirm conversations persist.
