#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/common.sh"

migrations_dir=""

usage() {
  cat <<'USAGE'
Usage: migrate.sh --migrations-dir DIRECTORY

Apply pending Cabanon PostgreSQL migrations in ascending numeric order.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --migrations-dir)
      (($# >= 2)) || fail "--migrations-dir requires a directory."
      migrations_dir="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${migrations_dir}" ]] || fail "--migrations-dir is required."
[[ -d "${migrations_dir}" ]] || fail "Migrations directory does not exist: ${migrations_dir}"

require_root
require_command cat
require_command psql
require_command runuser

mapfile -t migration_paths < <(find "${migrations_dir}" -maxdepth 1 -type f -name '[0-9]*_*.sql' -print | LC_ALL=C sort -V)
((${#migration_paths[@]} > 0)) || fail "No migration files were found in ${migrations_dir}."

declare -A seen_versions=()
for migration_path in "${migration_paths[@]}"; do
  migration_file="$(basename "${migration_path}")"
  version_text="${migration_file%%_*}"
  migration_name="${migration_file#*_}"
  migration_name="${migration_name%.sql}"
  [[ "${version_text}" =~ ^[0-9]+$ && "${migration_name}" =~ ^[A-Za-z0-9_-]+$ ]] \
    || fail "Migration name is invalid: ${migration_file}"
  version="$((10#${version_text}))"
  [[ -z "${seen_versions[${version}]:-}" ]] \
    || fail "More than one migration uses version ${version}."
  seen_versions[${version}]="${migration_file}"
done

schema_migrations_exists="$(runuser -u postgres -- psql --dbname=cabanon --tuples-only --no-align \
  --command="SELECT to_regclass('public.schema_migrations') IS NOT NULL;" | tr -d '[:space:]')"

for migration_path in "${migration_paths[@]}"; do
  migration_file="$(basename "${migration_path}")"
  version_text="${migration_file%%_*}"
  migration_name="${migration_file#*_}"
  migration_name="${migration_name%.sql}"

  version="$((10#${version_text}))"

  if [[ "${schema_migrations_exists}" == "t" ]]; then
    applied="$(runuser -u postgres -- psql --dbname=cabanon --tuples-only --no-align \
      --command="SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = ${version});" | tr -d '[:space:]')"
    [[ "${applied}" == "t" ]] && continue
  fi

  log "Applying migration ${migration_file}."
  {
    printf '%s\n' "SET ROLE cabanon_owner;"
    cat "${migration_path}"
  } | runuser -u postgres -- psql --dbname=cabanon --set=ON_ERROR_STOP=1

  runuser -u postgres -- psql --dbname=cabanon --set=ON_ERROR_STOP=1 \
    --command="SET ROLE cabanon_owner; INSERT INTO schema_migrations (version, name) VALUES (${version}, '${migration_name}') ON CONFLICT (version) DO NOTHING;"

  schema_migrations_exists="t"
done

log "Database migrations are up to date."
