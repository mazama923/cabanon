#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/common.sh"

release_dir=""
staging_dir=""

usage() {
  cat <<'USAGE'
Usage: deploy.sh --release-dir DIRECTORY

Verify and deploy a Cabanon release bundle without prompting for input.
USAGE
}

cleanup() {
  if [[ -n "${staging_dir}" && -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --release-dir)
      (($# >= 2)) || fail "--release-dir requires a directory."
      release_dir="$2"
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

[[ -n "${release_dir}" ]] || fail "--release-dir is required."

require_root
require_debian_13
require_systemd
require_command tar
require_command install
require_command readlink
require_command runuser
require_command psql
id cabanon >/dev/null 2>&1 || fail "Service account cabanon is missing. Run the interactive installer first."

release_dir="$(verify_release_bundle "${release_dir}")"
manifest_path="${release_dir}/manifest.json"
release_version="$(release_manifest_string "${manifest_path}" "release_version")"
otp_major="$(release_manifest_integer "${manifest_path}" "erlang_otp_major")"
otp_version="$(release_manifest_string "${manifest_path}" "erlang_otp_version")"
require_expected_erlang_runtime "${otp_major}" "${otp_version}"

[[ -f "${CABANON_ENV_FILE}" ]] \
  || fail "${CABANON_ENV_FILE} is missing. Run the interactive installer before deploying updates."
cabanon_environment="$(environment_value "${CABANON_ENV_FILE}" "CABANON_ENV")"
[[ "${cabanon_environment}" == "production" ]] \
  || fail "${CABANON_ENV_FILE} must set CABANON_ENV=production for deployment."
bind_address="$(environment_value "${CABANON_ENV_FILE}" "CABANON_BIND_ADDRESS")"
port="$(environment_value "${CABANON_ENV_FILE}" "CABANON_PORT")"
is_valid_tcp_port "${port}" \
  || fail "${CABANON_ENV_FILE} contains an invalid CABANON_PORT: ${port}."
ready_url="$(local_http_url "${bind_address}" "${port}" "/readyz")"

target_dir="${CABANON_RELEASES_DIR}/${release_version}"
[[ ! -e "${target_dir}" ]] \
  || fail "Release ${release_version} is already installed at ${target_dir}; releases are immutable."

install -d -o root -g cabanon -m 0755 "${CABANON_RELEASES_DIR}"
install -d -o cabanon -g cabanon -m 0750 /var/lib/cabanon

log "Verifying the Erlang shipment checksum."
(
  cd "${release_dir}"
  sha256sum --check --strict cabanon-erlang-shipment.tar.gz.sha256
) || fail "Erlang shipment checksum verification failed."

mapfile -t shipment_entries < <(tar -tzf "${release_dir}/cabanon-erlang-shipment.tar.gz")
((${#shipment_entries[@]} > 0)) || fail "Erlang shipment archive is empty."
for shipment_entry in "${shipment_entries[@]}"; do
  [[ "${shipment_entry}" == "erlang-shipment/" || "${shipment_entry}" == erlang-shipment/* ]] \
    || fail "Erlang shipment archive contains an unexpected path: ${shipment_entry}"
done

staging_dir="$(mktemp -d "${CABANON_RELEASES_DIR}/.staging.${release_version}.XXXXXX")"
tar -xzf "${release_dir}/cabanon-erlang-shipment.tar.gz" \
  --no-same-owner --no-same-permissions --strip-components=1 -C "${staging_dir}"
[[ -x "${staging_dir}/entrypoint.sh" ]] \
  || fail "Erlang shipment does not provide an executable entrypoint.sh."

cp -a "${release_dir}/frontend" "${staging_dir}/frontend"
cp -a "${release_dir}/migrations" "${staging_dir}/migrations"
install -m 0644 "${release_dir}/manifest.json" "${staging_dir}/manifest.json"
chown -R root:cabanon "${staging_dir}"
chmod 0750 "${staging_dir}"

previous_release=""
if [[ -L "${CABANON_CURRENT_LINK}" ]]; then
  previous_release="$(readlink -f "${CABANON_CURRENT_LINK}")"
  case "${previous_release}" in
    "${CABANON_RELEASES_DIR}"/*) ;;
    *) fail "Current release link does not point inside ${CABANON_RELEASES_DIR}." ;;
  esac
fi

log "Applying database migrations for release ${release_version}."
"${script_dir}/migrate.sh" --migrations-dir "${staging_dir}/migrations"

log "Installing release ${release_version}."
mv "${staging_dir}" "${target_dir}"
staging_dir=""

runuser -u postgres -- psql --dbname=cabanon --set=ON_ERROR_STOP=1 --command="
  SET ROLE cabanon_owner;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO cabanon_app;
  GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cabanon_app;
"

rollback() {
  if [[ -n "${previous_release}" ]]; then
    warn "Restoring the previous release after deployment failure."
    atomic_replace_symlink "${previous_release}" "${CABANON_CURRENT_LINK}"
    if ! systemctl restart "${CABANON_SERVICE_NAME}"; then
      fail "Deployment failed and the previous release could not be restarted. Inspect: journalctl -u ${CABANON_SERVICE_NAME}."
    fi
    if ! wait_for_http_endpoint "$(local_http_url "${bind_address}" "${port}" "/readyz")"; then
      fail "Deployment failed and the previous release is not ready. Inspect: journalctl -u ${CABANON_SERVICE_NAME}."
    fi
  else
    warn "Deployment failed with no previous release to restore."
    rm -f "${CABANON_CURRENT_LINK}"
    systemctl stop "${CABANON_SERVICE_NAME}" || true
  fi
}

atomic_replace_symlink "${target_dir}" "${CABANON_CURRENT_LINK}"

if ! systemctl restart "${CABANON_SERVICE_NAME}"; then
  rollback
  fail "Deployment failed while restarting ${CABANON_SERVICE_NAME}."
fi

if ! wait_for_http_endpoint "${ready_url}"; then
  rollback
  fail "Deployment failed because ${ready_url} did not become ready. Inspect: journalctl -u ${CABANON_SERVICE_NAME}."
fi

log "Release ${release_version} is deployed and ready."
