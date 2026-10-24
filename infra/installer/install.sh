#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
release_dir="$(cd -P "${script_dir}/.." && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/common.sh"

readonly minimum_free_kib=1048576
environment_tmp=""
postgres_hba_tmp=""

cleanup() {
  if [[ -n "${environment_tmp}" && -e "${environment_tmp}" ]]; then
    rm -f "${environment_tmp}"
  fi
  if [[ -n "${postgres_hba_tmp}" && -e "${postgres_hba_tmp}" ]]; then
    rm -f "${postgres_hba_tmp}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: install.sh

Interactively install Cabanon and the release bundle containing this script.
USAGE
}

confirm() {
  local response
  read -r -p "$1 [y/N]: " response
  [[ "${response}" == "y" || "${response}" == "Y" ]]
}

is_safe_bind_address() {
  local address="$1"

  [[ -n "${address}" && "${address}" != "127.0.0.1" && "${address}" != "::1" ]] \
    || return 1
  [[ "${address}" =~ ^[0-9A-Fa-f:.]+$ ]]
}

is_valid_allowed_origin() {
  local origin="$1"

  [[ "${origin}" =~ ^https?://([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?$ ]] \
    || return 1
  if [[ "${origin}" =~ :([0-9]{1,5})$ ]]; then
    is_valid_tcp_port "${BASH_REMATCH[1]}"
  fi
}

read_new_secrets() {
  local response

  read -r -p "Provide PostgreSQL and application secrets instead of generating them? [y/N]: " response
  if [[ "${response}" == "y" || "${response}" == "Y" ]]; then
    read -r -s -p "PostgreSQL password (at least 32 URL-safe characters): " app_password
    printf '\n' >&2
    read -r -s -p "CABANON_SECRET_KEY_BASE (64 hexadecimal characters): " secret_key_base
    printf '\n' >&2
  else
    app_password="$(openssl rand -hex 32)"
    secret_key_base="$(openssl rand -hex 32)"
  fi

  [[ "${app_password}" =~ ^[A-Za-z0-9._~-]{32,}$ ]] \
    || fail "PostgreSQL password must contain at least 32 URL-safe characters."
  [[ "${secret_key_base}" =~ ^[A-Fa-f0-9]{64}$ ]] \
    || fail "CABANON_SECRET_KEY_BASE must be exactly 64 hexadecimal characters."
}

write_environment() {
  environment_tmp="$(mktemp /etc/cabanon/.cabanon.env.XXXXXX)"
  cat >"${environment_tmp}" <<ENVIRONMENT
CABANON_ENV=production
CABANON_SECRET_KEY_BASE=${secret_key_base}
CABANON_DATABASE_URL=postgresql://cabanon_app:${app_password}@127.0.0.1:5432/cabanon?sslmode=disable
CABANON_BIND_ADDRESS=${bind_address}
CABANON_PORT=${port}
CABANON_ALLOWED_ORIGIN=${allowed_origin}
ENVIRONMENT
  chown root:root "${environment_tmp}"
  chmod 0600 "${environment_tmp}"
  mv -f "${environment_tmp}" "${CABANON_ENV_FILE}"
  environment_tmp=""
}

load_existing_secrets() {
  local database_url

  secret_key_base="$(environment_value "${CABANON_ENV_FILE}" "CABANON_SECRET_KEY_BASE")"
  database_url="$(environment_value "${CABANON_ENV_FILE}" "CABANON_DATABASE_URL")"
  [[ "${secret_key_base}" =~ ^[A-Fa-f0-9]{64}$ ]] \
    || fail "Existing CABANON_SECRET_KEY_BASE must be exactly 64 hexadecimal characters."
  if [[ "${database_url}" =~ ^postgresql://cabanon_app:([A-Za-z0-9._~-]{32,})@127\.0\.0\.1:5432/cabanon\?sslmode=disable$ ]]; then
    app_password="${BASH_REMATCH[1]}"
  else
    fail "Existing CABANON_DATABASE_URL does not match the Cabanon local PostgreSQL configuration."
  fi
}

postgresql_scalar() {
  runuser -u postgres -- psql --tuples-only --no-align --set=ON_ERROR_STOP=1 \
    --command="$1" | tr -d '[:space:]'
}

postgresql_object_exists() {
  local query="$1"
  [[ "$(postgresql_scalar "${query}")" == "t" ]]
}

configure_postgresql_network() {
  local cluster_info pg_version pg_cluster hba_file hba_tmp attempt

  require_command pg_lsclusters
  require_command pg_conftool
  cluster_info="$(pg_lsclusters --no-header | awk 'NR == 1 {print $1 " " $2}')"
  [[ -n "${cluster_info}" ]] || fail "No PostgreSQL cluster was created by the Debian packages."
  read -r pg_version pg_cluster <<<"${cluster_info}"
  [[ -n "${pg_version}" && -n "${pg_cluster}" ]] || fail "Unable to identify the PostgreSQL cluster."

  pg_conftool "${pg_version}" "${pg_cluster}" set listen_addresses "'127.0.0.1'"
  pg_conftool "${pg_version}" "${pg_cluster}" set password_encryption "scram-sha-256"

  hba_file="/etc/postgresql/${pg_version}/${pg_cluster}/pg_hba.conf"
  [[ -f "${hba_file}" ]] || fail "PostgreSQL host-based authentication file is missing: ${hba_file}"
  hba_tmp="$(mktemp "${hba_file}.XXXXXX")"
  postgres_hba_tmp="${hba_tmp}"
  cat >"${hba_tmp}" <<'HBA'
# Managed by the Cabanon installer. PostgreSQL remains local-only.
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
HBA
  chown postgres:postgres "${hba_tmp}"
  chmod 0640 "${hba_tmp}"
  mv -f "${hba_tmp}" "${hba_file}"
  postgres_hba_tmp=""

  systemctl restart "postgresql@${pg_version}-${pg_cluster}.service" \
    || fail "Unable to restart PostgreSQL cluster ${pg_version}/${pg_cluster}. Inspect: journalctl -u postgresql@${pg_version}-${pg_cluster}.service."

  for ((attempt = 1; attempt <= 30; attempt += 1)); do
    if runuser -u postgres -- psql --dbname=postgres --quiet --command="SELECT 1;" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  fail "PostgreSQL cluster ${pg_version}/${pg_cluster} did not accept local connections. Inspect: pg_lsclusters; journalctl -u postgresql@${pg_version}-${pg_cluster}.service."
}

create_database_roles_and_database() {
  local owner_exists app_exists database_exists database_owner

  owner_exists="false"
  app_exists="false"
  database_exists="false"
  postgresql_object_exists "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cabanon_owner');" \
    && owner_exists="true"
  postgresql_object_exists "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cabanon_app');" \
    && app_exists="true"
  postgresql_object_exists "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'cabanon');" \
    && database_exists="true"

  if [[ "${existing_environment}" == "false" ]]; then
    [[ "${owner_exists}" == "false" && "${app_exists}" == "false" && "${database_exists}" == "false" ]] \
      || fail "Cabanon PostgreSQL roles or database already exist without ${CABANON_ENV_FILE}; refusing an ambiguous destructive action."
  fi

  if [[ "${owner_exists}" == "false" ]]; then
    runuser -u postgres -- psql --set=ON_ERROR_STOP=1 --command="CREATE ROLE cabanon_owner NOLOGIN;"
  fi
  if [[ "${app_exists}" == "false" ]]; then
    printf "CREATE ROLE cabanon_app LOGIN PASSWORD '%s';\n" "${app_password}" \
      | runuser -u postgres -- psql --set=ON_ERROR_STOP=1
  else
    printf "ALTER ROLE cabanon_app LOGIN PASSWORD '%s';\n" "${app_password}" \
      | runuser -u postgres -- psql --set=ON_ERROR_STOP=1
  fi
  if [[ "${database_exists}" == "false" ]]; then
    runuser -u postgres -- psql --set=ON_ERROR_STOP=1 --command="CREATE DATABASE cabanon OWNER cabanon_owner;"
  fi

  database_owner="$(postgresql_scalar "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'cabanon';")"
  [[ "${database_owner}" == "cabanon_owner" ]] \
    || fail "Existing cabanon database is not owned by cabanon_owner; refusing an ambiguous change."

  runuser -u postgres -- psql --dbname=cabanon --set=ON_ERROR_STOP=1 --command="
    REVOKE ALL ON DATABASE cabanon FROM PUBLIC;
    GRANT CONNECT ON DATABASE cabanon TO cabanon_app;
    ALTER SCHEMA public OWNER TO cabanon_owner;
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE ON SCHEMA public TO cabanon_app;
    ALTER DEFAULT PRIVILEGES FOR ROLE cabanon_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cabanon_app;
    ALTER DEFAULT PRIVILEGES FOR ROLE cabanon_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cabanon_app;
  "
}


while (($# > 0)); do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_root
require_debian_13
require_systemd
require_command apt-get
require_command openssl
require_command sha256sum
require_free_space_kib / "${minimum_free_kib}"
release_dir="$(verify_release_bundle "${release_dir}")"

existing_environment="false"
if [[ -f "${CABANON_ENV_FILE}" ]]; then
  existing_environment="true"
  cabanon_environment="$(environment_value "${CABANON_ENV_FILE}" "CABANON_ENV")"
  [[ "${cabanon_environment}" == "production" ]] \
    || fail "Existing environment must set CABANON_ENV=production."
  bind_address="$(environment_value "${CABANON_ENV_FILE}" "CABANON_BIND_ADDRESS")"
  port="$(environment_value "${CABANON_ENV_FILE}" "CABANON_PORT")"
  is_valid_tcp_port "${port}" \
    || fail "Existing CABANON_PORT is invalid."
  allowed_origin="$(environment_value "${CABANON_ENV_FILE}" "CABANON_ALLOWED_ORIGIN")"
  is_valid_allowed_origin "${allowed_origin}" \
    || fail "Existing CABANON_ALLOWED_ORIGIN is invalid; use an absolute http or https origin without a path."
  load_existing_secrets
  log "An existing Cabanon environment was found; existing secrets will be preserved and incomplete database setup will resume."
else
  read -r -p "Private Cabanon bind address: " bind_address
  is_safe_bind_address "${bind_address}" \
    || fail "Enter a non-loopback IPv4 or IPv6 address."
  read -r -p "Allowed browser origin (for example https://cabanon.example): " allowed_origin
  is_valid_allowed_origin "${allowed_origin}" \
    || fail "Enter an absolute http or https origin without a path."
  port="8080"
fi

release_version="$(release_manifest_string "${release_dir}/manifest.json" "release_version")"
printf '%s\n' "Installation summary:" >&2
printf '%s\n' "  Release: ${release_version}" >&2
printf '%s\n' "  Bind address: ${bind_address}" >&2
printf '%s\n' "  Allowed origin: ${allowed_origin}" >&2
printf '%s\n' "  PostgreSQL: local-only with SCRAM authentication" >&2
printf '%s\n' "  Service account: cabanon" >&2
confirm "Install this release and configure this host" || fail "Installation cancelled before system changes."

log "Refreshing APT package metadata."
apt-get update
require_apt_erlang_candidate "${CABANON_OTP_VERSION}"

log "Installing required Debian packages."
DEBIAN_FRONTEND=noninteractive apt-get install --yes \
  erlang \
  postgresql \
  postgresql-client \
  ca-certificates \
  curl \
  openssl \
  iproute2
require_expected_erlang_runtime "${CABANON_OTP_MAJOR}" "${CABANON_OTP_VERSION}"
is_local_non_loopback_address "${bind_address}" \
  || fail "Bind address ${bind_address} is not configured on this host."

if ! getent passwd cabanon >/dev/null 2>&1; then
  useradd --system --user-group --home-dir /var/lib/cabanon --create-home \
    --shell /usr/sbin/nologin cabanon
else
  service_shell="$(getent passwd cabanon | awk -F: '{print $7}')"
  [[ "${service_shell}" == */nologin ]] \
    || fail "Existing cabanon account is not a non-login service account."
fi

install -d -o root -g root -m 0750 /etc/cabanon
install -d -o root -g cabanon -m 0755 "${CABANON_RELEASES_DIR}"
install -d -o cabanon -g cabanon -m 0750 /var/lib/cabanon

if [[ "${existing_environment}" == "false" ]]; then
  read_new_secrets
  write_environment
fi

configure_postgresql_network
create_database_roles_and_database

install -o root -g root -m 0644 "${release_dir}/systemd/cabanon.service" \
  "/etc/systemd/system/${CABANON_SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${CABANON_SERVICE_NAME}"

"${script_dir}/deploy.sh" --release-dir "${release_dir}"

health_url="$(local_http_url "${bind_address}" "${port}" "/healthz")"
ready_url="$(local_http_url "${bind_address}" "${port}" "/readyz")"
wait_for_http_endpoint "${health_url}" \
  || fail "Application liveness check failed at ${health_url}. Inspect: journalctl -u ${CABANON_SERVICE_NAME}."
wait_for_http_endpoint "${ready_url}" \
  || fail "Application readiness check failed at ${ready_url}. Inspect: journalctl -u ${CABANON_SERVICE_NAME}."

log "Cabanon installation completed successfully."
