#!/usr/bin/env sh
set -eu

if [ -n "${OIDC_P12_BASE64:-}" ]; then
  export KEYMANAGER_KEYSTORE_PATH="${KEYMANAGER_KEYSTORE_PATH:-/tmp/oidckeystore.p12}"
  export OIDC_P12_PATH="${OIDC_P12_PATH:-/tmp/}"
  export OIDC_P12_FILENAME="${OIDC_P12_FILENAME:-oidckeystore.p12}"
  if ! printf '%s' "$OIDC_P12_BASE64" | base64 -d > "$KEYMANAGER_KEYSTORE_PATH" 2>/dev/null; then
    printf '%s' "$OIDC_P12_BASE64" | base64 -D > "$KEYMANAGER_KEYSTORE_PATH"
  fi
fi

exec java \
  -Dserver.port="${PORT:-8099}" \
  -Dspring.profiles.active="${SPRING_PROFILES_ACTIVE:-default,prod}" \
  -jar target/mimoto-0.22.0.jar
