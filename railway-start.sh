#!/usr/bin/env sh
set -eu

if [ -z "${DATABASE_URL:-}" ] && [ -n "${DATABASE_PRIVATE_URL:-}" ]; then
  export DATABASE_URL="$DATABASE_PRIVATE_URL"
fi

if [ -z "${JDBC_DATABASE_URL:-}" ] && [ -n "${SPRING_DATASOURCE_URL:-}" ]; then
  export JDBC_DATABASE_URL="$SPRING_DATASOURCE_URL"
fi

if [ -z "${JDBC_DATABASE_URL:-}" ] && [ -n "${PGHOST:-}" ]; then
  export JDBC_DATABASE_URL="jdbc:postgresql://${PGHOST}:${PGPORT:-5432}/${PGDATABASE:-postgres}"
elif [ -z "${JDBC_DATABASE_URL:-}" ] && [ -n "${DATABASE_URL:-}" ]; then
  export JDBC_DATABASE_URL="$(printf '%s' "$DATABASE_URL" | sed 's#^postgresql://#jdbc:postgresql://#; s#^postgres://#jdbc:postgresql://#')"
fi

if [ -z "${PGUSER:-}" ] && [ -n "${SPRING_DATASOURCE_USERNAME:-}" ]; then
  export PGUSER="$SPRING_DATASOURCE_USERNAME"
fi

if [ -z "${PGPASSWORD:-}" ] && [ -n "${SPRING_DATASOURCE_PASSWORD:-}" ]; then
  export PGPASSWORD="$SPRING_DATASOURCE_PASSWORD"
fi

if [ -z "${REDIS_URL:-}" ] && [ -n "${REDIS_PRIVATE_URL:-}" ]; then
  export REDIS_URL="$REDIS_PRIVATE_URL"
fi

if [ -z "${REDIS_HOST:-}" ] && [ -n "${REDISHOST:-}" ]; then
  export REDIS_HOST="$REDISHOST"
fi

if [ -z "${REDIS_PORT:-}" ] && [ -n "${REDISPORT:-}" ]; then
  export REDIS_PORT="$REDISPORT"
fi

if [ -z "${REDIS_PASSWORD:-}" ] && [ -n "${REDISPASSWORD:-}" ]; then
  export REDIS_PASSWORD="$REDISPASSWORD"
fi

if [ -n "${REDIS_URL:-}" ]; then
  export SESSION_STORE_TYPE="${SESSION_STORE_TYPE:-redis}"
  export CACHE_TYPE="${CACHE_TYPE:-redis}"
elif [ -n "${REDIS_HOST:-}" ]; then
  export SESSION_STORE_TYPE="${SESSION_STORE_TYPE:-redis}"
  export CACHE_TYPE="${CACHE_TYPE:-redis}"
fi

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

auto_init_db="${INIT_DB:-}"
if [ -z "$auto_init_db" ] && { [ -n "${PGHOST:-}" ] || [ -n "${DATABASE_URL:-}" ]; }; then
  auto_init_db=true
fi

if [ "$auto_init_db" = "true" ]; then
  if ! command -v psql >/dev/null 2>&1; then
    echo "Database bootstrap is enabled but psql is not available in the Railway image." >&2
    exit 1
  fi

  db_url="${DATABASE_URL:-}"
  if [ -z "$db_url" ]; then
    if [ -z "${PGHOST:-}" ] || [ -z "${PGUSER:-}" ] || [ -z "${PGPASSWORD:-}" ]; then
      echo "Database bootstrap requires DATABASE_URL or PGHOST, PGUSER, and PGPASSWORD." >&2
      exit 1
    fi
    db_url="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT:-5432}/${PGDATABASE:-postgres}"
  fi

  echo "Waiting for PostgreSQL..."
  ready=false
  for attempt in $(seq 1 30); do
    if psql "$db_url" -v ON_ERROR_STOP=1 -tAc "select 1" >/dev/null 2>&1; then
      ready=true
      break
    fi
    echo "PostgreSQL is not ready yet (${attempt}/30)."
    sleep 2
  done

  if [ "$ready" != "true" ]; then
    echo "PostgreSQL did not become ready in time." >&2
    exit 1
  fi

  existing_table="$(psql "$db_url" -tAc "select to_regclass('mimoto.key_policy_def')" | tr -d '[:space:]')"
  if [ "$existing_table" != "mimoto.key_policy_def" ]; then
    echo "Initializing Mimoto PostgreSQL schema..."
    db_name="$(psql "$db_url" -tAc "select current_database()" | tr -d '[:space:]')"
    psql "$db_url" -v ON_ERROR_STOP=1 -v dbname="$db_name" <<'SQL'
CREATE SCHEMA IF NOT EXISTS mimoto;
ALTER DATABASE :"dbname" SET search_path TO mimoto,pg_catalog,public;
SQL

    export PGOPTIONS="-c search_path=mimoto,pg_catalog,public"
    for ddl_file in \
      db_scripts/inji_mimoto/ddl/mimoto-key_alias.sql \
      db_scripts/inji_mimoto/ddl/mimoto-key_policy_def.sql \
      db_scripts/inji_mimoto/ddl/mimoto-key_store.sql \
      db_scripts/inji_mimoto/ddl/mimoto-ca_cert_store.sql \
      db_scripts/inji_mimoto/ddl/mimoto-user_metadata.sql \
      db_scripts/inji_mimoto/ddl/mimoto-wallet.sql \
      db_scripts/inji_mimoto/ddl/mimoto-proof_signing_keys.sql \
      db_scripts/inji_mimoto/ddl/mimoto-verifiable_credentials.sql \
      db_scripts/inji_mimoto/ddl/mimoto-trusted-verifiers.sql \
      db_scripts/inji_mimoto/ddl/mimoto-verifiable_presentations.sql
    do
      psql "$db_url" -v ON_ERROR_STOP=1 -f "$ddl_file"
    done

    psql "$db_url" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO mimoto.key_policy_def
  (app_id, key_validity_duration, pre_expire_days, access_allowed, is_active, cr_by, cr_dtimes)
VALUES
  ('ROOT', 2920, 1125, 'NA', TRUE, 'mosipadmin', now()),
  ('MIMOTO', 1095, 60, 'NA', TRUE, 'mosipadmin', now()),
  ('BASE', 730, 60, 'NA', TRUE, 'mosipadmin', now())
ON CONFLICT (app_id) DO NOTHING;
SQL
    unset PGOPTIONS
    echo "Mimoto PostgreSQL schema initialized."
  else
    echo "Mimoto PostgreSQL schema already exists."
  fi
fi

set -- \
  "-Dserver.address=${SERVER_ADDRESS:-0.0.0.0}" \
  "-Dserver.port=${PORT:-8099}" \
  "-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE:-default,prod}" \
  "-Dspring.cloud.config.enabled=${SPRING_CLOUD_CONFIG_ENABLED:-false}"

if [ -n "${JDBC_DATABASE_URL:-}" ]; then
  set -- "$@" "-Dspring.datasource.url=${JDBC_DATABASE_URL}" "-Dkeymanager_database_url=${JDBC_DATABASE_URL}"
fi

if [ -n "${PGUSER:-}" ]; then
  set -- "$@" "-Dspring.datasource.username=${PGUSER}" "-Dkeymanager_database_username=${PGUSER}"
fi

if [ -n "${PGPASSWORD:-}" ]; then
  set -- "$@" "-Dspring.datasource.password=${PGPASSWORD}" "-Dkeymanager_database_password=${PGPASSWORD}"
fi

if [ -n "${REDIS_URL:-}" ]; then
  set -- "$@" "-Dspring.data.redis.url=${REDIS_URL}"
fi

exec java "$@" -jar target/mimoto-0.22.0.jar
