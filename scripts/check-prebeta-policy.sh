#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'pre-beta policy check failed: %s\n' "$1" >&2
  exit 1
}

check_absent() {
  local pattern="$1"
  shift
  if grep -RInE "$pattern" "$@" >/tmp/toki-prebeta-policy-hit.txt; then
    cat /tmp/toki-prebeta-policy-hit.txt >&2
    fail "forbidden runtime media pattern matched: $pattern"
  fi
}

check_absent 'turns?://' cmd internal Sources/TokiApp
check_absent 'turns?://' Sources/TokiCore --exclude='ICEConfig.swift' --exclude='BetaReleaseDiagnostics.swift'
check_absent '(^|[^A-Za-z])(SFU|MCU)([^A-Za-z]|$)' cmd internal Sources/TokiApp Sources/TokiCore
check_absent 'media[-_ ]?upload|audio[-_ ]?upload|server[-_ ]?media|raw[-_ ]?audio[-_ ]?upload' cmd internal Sources/TokiApp Sources/TokiCore

grep -q 'RelayPolicy: "disabled"' internal/httpapi/server.go || fail 'backend ICE config must return relayPolicy disabled'
grep -q 'relayPolicy == \.disabled' Sources/TokiCore/ICEConfig.swift || fail 'client strict ICE validation must require disabled relay policy'
grep -q '"turnDisabled": true' release/beta-release.json || fail 'release config must keep TURN disabled'
grep -q '"serverMediaDisabled": true' release/beta-release.json || fail 'release config must keep server media disabled'

printf 'pre-beta policy check passed\n'
