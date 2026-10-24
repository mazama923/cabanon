#!/usr/bin/env bash
set -euo pipefail

readonly CABANON_OS_ID="debian"
readonly CABANON_OS_VERSION="13"
readonly CABANON_OTP_MAJOR="27"
readonly CABANON_OTP_VERSION="27.3.4.1"
readonly CABANON_INSTALL_ROOT="/opt/cabanon"
readonly CABANON_RELEASES_DIR="${CABANON_INSTALL_ROOT}/releases"
readonly CABANON_CURRENT_LINK="${CABANON_INSTALL_ROOT}/current"
readonly CABANON_ENV_FILE="/etc/cabanon/cabanon.env"
readonly CABANON_SERVICE_NAME="cabanon.service"

log() {
  printf '%s\n' "==> $*" >&2
}

warn() {
  printf '%s\n' "WARNING: $*" >&2
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
}

require_debian_13() {
  [[ -r /etc/os-release ]] || fail "Cannot identify the operating system because /etc/os-release is missing."

  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "${CABANON_OS_ID}" && "${VERSION_ID:-}" == "${CABANON_OS_VERSION}" ]] \
    || fail "Cabanon supports Debian 13 only. Detected ${ID:-unknown} ${VERSION_ID:-unknown}."
}

require_systemd() {
  [[ -d /run/systemd/system ]] || fail "systemd is required but is not running."
  require_command systemctl
}

release_manifest_string() {
  local manifest_path="$1"
  local key="$2"
  local value

  value="$(sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$/\\1/p" "${manifest_path}")"
  [[ -n "${value}" ]] || fail "Release manifest is missing a valid string field: ${key}"
  printf '%s\n' "${value}"
}

release_manifest_integer() {
  local manifest_path="$1"
  local key="$2"
  local value

  value="$(sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,?[[:space:]]*$/\\1/p" "${manifest_path}")"
  [[ -n "${value}" ]] || fail "Release manifest is missing a valid integer field: ${key}"
  printf '%s\n' "${value}"
}

validate_release_version() {
  local release_version="$1"
  [[ "${release_version}" =~ ^[A-Za-z0-9._-]+$ ]] \
    || fail "Release version contains unsafe characters."
}

verify_release_bundle() {
  local release_dir="$1"
  local manifest_path release_version target_os otp_major otp_version

  [[ -d "${release_dir}" ]] || fail "Release directory does not exist: ${release_dir}"
  release_dir="$(cd -P "${release_dir}" && pwd)"

  for required_path in \
    "cabanon-erlang-shipment.tar.gz" \
    "cabanon-erlang-shipment.tar.gz.sha256" \
    "checksums.sha256" \
    "manifest.json" \
    "frontend" \
    "migrations" \
    "systemd/cabanon.service" \
    "installer/install.sh" \
    "installer/deploy.sh" \
    "installer/migrate.sh" \
    "installer/lib/common.sh"; do
    [[ -e "${release_dir}/${required_path}" ]] \
      || fail "Release bundle is incomplete; missing ${required_path}."
  done

  [[ -f "${release_dir}/frontend/index.html" ]] \
    || fail "Release bundle is incomplete; missing frontend/index.html."

  require_command sha256sum
  log "Verifying release checksums."
  (
    cd "${release_dir}"
    sha256sum --check --strict checksums.sha256 >&2
  ) || fail "Release checksum verification failed. Download the release again."

  manifest_path="${release_dir}/manifest.json"
  release_version="$(release_manifest_string "${manifest_path}" "release_version")"
  target_os="$(release_manifest_string "${manifest_path}" "target_os")"
  otp_major="$(release_manifest_integer "${manifest_path}" "erlang_otp_major")"
  otp_version="$(release_manifest_string "${manifest_path}" "erlang_otp_version")"

  validate_release_version "${release_version}"
  [[ "${target_os}" == "debian-13" ]] \
    || fail "Release targets ${target_os}, not debian-13."
  [[ "${otp_major}" == "${CABANON_OTP_MAJOR}" ]] \
    || fail "Release requires OTP ${otp_major}; this installer supports OTP ${CABANON_OTP_MAJOR}."
  [[ "${otp_version}" == "${CABANON_OTP_VERSION}" ]] \
    || fail "Release requires OTP ${otp_version}; expected ${CABANON_OTP_VERSION}."

  printf '%s\n' "${release_dir}"
}

erlang_otp_major() {
  require_command erl
  erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' \
    || fail "Unable to query the installed Erlang runtime."
}

require_expected_erlang_runtime() {
  local expected_major="$1"
  local expected_version="$2"
  local installed_major package_version normalized_package_version

  installed_major="$(erlang_otp_major)"
  [[ "${installed_major}" == "${expected_major}" ]] \
    || fail "Installed Erlang OTP major version is ${installed_major}; expected ${expected_major}."

  require_command dpkg-query
  package_version="$(dpkg-query --showformat='${Version}' --show erlang-base 2>/dev/null)" \
    || fail "The erlang-base package is not installed."
  normalized_package_version="${package_version#*:}"
  [[ "${normalized_package_version}" == "${expected_version}"* ]] \
    || fail "Installed erlang-base version is ${package_version}; expected ${expected_version} from Debian 13."
}

require_apt_erlang_candidate() {
  local expected_version="$1"
  local candidate normalized_candidate

  require_command apt-cache
  candidate="$(apt-cache policy erlang-base | awk '/Candidate:/{print $2; exit}')"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]] \
    || fail "APT does not offer an erlang-base package. Check configured Debian repositories."

  normalized_candidate="${candidate#*:}"
  [[ "${normalized_candidate}" == "${expected_version}"* ]] \
    || fail "APT offers erlang-base ${candidate}; expected Debian 13 OTP ${expected_version}."
}

require_free_space_kib() {
  local path="$1"
  local required_kib="$2"
  local available_kib

  require_command df
  available_kib="$(df -Pk "${path}" | awk 'NR == 2 {print $4}')"
  [[ "${available_kib}" =~ ^[0-9]+$ ]] || fail "Unable to determine free disk space for ${path}."
  (( available_kib >= required_kib )) \
    || fail "At least ${required_kib} KiB free space is required at ${path}; only ${available_kib} KiB is available."
}

is_local_non_loopback_address() {
  local address="$1"

  [[ -n "${address}" && "${address}" != "127.0.0.1" && "${address}" != "::1" ]] || return 1
  ip -o addr show | awk '{split($4, address, "/"); print address[1]}' | grep -Fqx -- "${address}"
}

environment_value() {
  local environment_file="$1"
  local key="$2"
  local value

  [[ -r "${environment_file}" ]] || fail "Environment file is unreadable: ${environment_file}"
  value="$(sed -nE "s/^${key}=([^[:space:]]+)$/\\1/p" "${environment_file}")"
  [[ -n "${value}" ]] || fail "Environment file is missing ${key}."
  printf '%s\n' "${value}"
}

is_valid_tcp_port() {
  local port="$1"
  local numeric_port

  [[ "${port}" =~ ^[0-9]{1,5}$ ]] || return 1
  numeric_port="$((10#${port}))"
  (( numeric_port >= 1 && numeric_port <= 65535 ))
}

local_http_url() {
  local bind_address="$1"
  local port="$2"
  local path="$3"

  is_valid_tcp_port "${port}" || fail "Invalid local HTTP port: ${port}"
  if [[ "${bind_address}" == *:* ]]; then
    printf 'http://[%s]:%s%s\n' "${bind_address}" "${port}" "${path}"
  else
    printf 'http://%s:%s%s\n' "${bind_address}" "${port}" "${path}"
  fi
}

wait_for_http_endpoint() {
  local url="$1"
  local attempts="${2:-30}"
  local attempt

  require_command curl
  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    if curl --fail --silent --show-error --max-time 5 "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

atomic_replace_symlink() {
  local target="$1"
  local link_path="$2"
  local temporary_link="${link_path}.new.$$"

  rm -f "${temporary_link}"
  ln -s "${target}" "${temporary_link}"
  mv -Tf "${temporary_link}" "${link_path}"
}
