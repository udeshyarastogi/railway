#!/usr/bin/env sh
set -eu

if [ -n "${OIDC_P12_BASE64:-}" ]; then
  export KEYMANAGER_KEYSTORE_PATH="${KEYMANAGER_KEYSTORE_PATH:-/tmp/oidckeystore.p12}"
  export OIDC_P12_PATH="${OIDC_P12_PATH:-/tmp/}"
  export OIDC_P12_FILENAME="${OIDC_P12_FILENAME:-oidckeystore.p12}"
  if ! printf '%s' "$OIDC_P12_BASE64" | base64 -d > "$KEYMANAGER_KEYSTORE_PATH" 2>/dev/null; then
    printf '%s' "$OIDC_P12_BASE64" | base64 -D > "$KEYMANAGER_KEYSTORE_PATH"
  fi
else
  export KEYMANAGER_KEYSTORE_PATH="${KEYMANAGER_KEYSTORE_PATH:-/tmp/oidckeystore.p12}"
  export OIDC_P12_PATH="${OIDC_P12_PATH:-/tmp/}"
  export OIDC_P12_FILENAME="${OIDC_P12_FILENAME:-oidckeystore.p12}"
  export OIDC_P12_PASSWORD="${OIDC_P12_PASSWORD:-replace-me}"
  export KEYMANAGER_KEYSTORE_PASSWORD="${KEYMANAGER_KEYSTORE_PASSWORD:-$OIDC_P12_PASSWORD}"
  if [ ! -f "$KEYMANAGER_KEYSTORE_PATH" ] && command -v keytool >/dev/null 2>&1; then
    keytool -genkeypair \
      -alias "${MOSIP_PARTNER_P12_ALIAS:-partner}" \
      -keyalg RSA \
      -keysize 2048 \
      -storetype PKCS12 \
      -keystore "$KEYMANAGER_KEYSTORE_PATH" \
      -storepass "$KEYMANAGER_KEYSTORE_PASSWORD" \
      -keypass "$KEYMANAGER_KEYSTORE_PASSWORD" \
      -dname "CN=Railway Temporary, OU=Mimoto, O=Inji, L=Bangalore, ST=KA, C=IN" \
      -validity 3650 >/dev/null 2>&1 || true
  fi
fi

exec java \
  -Dserver.port="${PORT:-8099}" \
  -Dspring.profiles.active="${SPRING_PROFILES_ACTIVE:-default,prod}" \
  -Dspring.cloud.config.enabled="${SPRING_CLOUD_CONFIG_ENABLED:-false}" \
  -jar target/mimoto-0.22.0.jar
