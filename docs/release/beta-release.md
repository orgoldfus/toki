# Beta Release Runbook

This runbook prepares direct private beta builds. It preserves the MVP rule that backend systems coordinate metadata only and never carry user audio.

## Release Configuration

The canonical beta release config is [`release/beta-release.json`](../../release/beta-release.json).

- Signing method: Developer ID Application.
- Update channel: `beta`.
- Update feed: Sparkle-compatible appcast from [`release/beta-appcast.template.xml`](../../release/beta-appcast.template.xml).
- Diagnostics: metadata-only, explicit user action, no audio, replay buffers, SDP bodies, ICE candidate bodies, auth tokens, magic-link tokens, or email addresses.
- Media policy: STUN-only discovery, TURN disabled, server media disabled.

## Local Signing And Notarization

Set these values in the release shell, not in tracked files:

```bash
export TOKI_DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)"
export TOKI_NOTARYTOOL_PROFILE="toki-notarytool-profile"
```

Build and sign the app archive:

```bash
rtk swift build -c release
codesign --force --deep --options runtime --timestamp --sign "$TOKI_DEVELOPER_ID_APPLICATION" .build/release/TokiApp
ditto -c -k --keepParent .build/release/TokiApp Toki.zip
```

Submit for notarization and staple the accepted result:

```bash
xcrun notarytool submit Toki.zip --keychain-profile "$TOKI_NOTARYTOOL_PROFILE" --wait
xcrun stapler staple .build/release/TokiApp
spctl --assess --type execute --verbose .build/release/TokiApp
```

Record the signing identity, notarization request ID, and `spctl` result in the pre-beta checklist before marking a build ready.

## Auto-Update Feed

Use the appcast template to publish each beta build. Replace:

- `__VERSION__` with `CFBundleShortVersionString`.
- `__BUILD__` with `CFBundleVersion`.
- `__SPARKLE_ED_SIGNATURE__` with the Sparkle archive signature.
- `__ARCHIVE_BYTES__` with the uploaded archive size.

Do not ship an auto-update build until a local update from version N to N+1 has been tested.

## Backend Deployment Checklist

- Apply `migrations/001_metadata.sql` before starting a PostgreSQL-backed beta service.
- Set `TOKI_DATABASE_URL` for the durable database.
- Set `TOKI_DEV_INVITES` only to the private beta allowlist.
- Terminate TLS at the edge or run the service behind an HTTPS reverse proxy.
- Confirm `/v1/ice-config` returns STUN URLs only and `"relayPolicy": "disabled"`.
- Confirm `/v1/realtime` carries presence, room membership, signaling metadata, and floor-control events only.
- Confirm structured logs include request ID, status code, event type, and available metadata IDs, with sensitive values redacted.

## Diagnostics And Crash Reporting

Client diagnostics exports are metadata-only and require explicit user action. They may include app version, macOS version, device model, permission states, selected device names, realtime event summaries, peer connection states, and redacted error messages.

Crash reporting remains disabled for beta until the selected provider can be configured and tested to exclude audio buffers, replay data, SDP bodies, ICE candidate bodies, auth tokens, magic-link tokens, and email addresses.

## Pre-Beta Gate

A build is not ready until all of these are true:

- Developer ID signing identity is recorded.
- Notarization is accepted and stapled.
- Update feed URL is recorded and version N to N+1 is tested.
- Backend version is recorded.
- QA matrix has no failed or blocked required cases.
- `scripts/check-prebeta-policy.sh` passes.
- `rtk swift test`, `rtk swift build`, and CI Go tests pass.
