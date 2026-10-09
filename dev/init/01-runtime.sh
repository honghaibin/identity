#!/usr/bin/env bash
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=app_password="$IDENTITY_DB_APP_PASSWORD" <<'SQL'
CREATE ROLE platform_runtime NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE identity_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS PASSWORD :'app_password';
GRANT platform_runtime TO identity_app;
GRANT CONNECT ON DATABASE identity TO identity_app;
SQL