#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -P "${script_dir}/.." && pwd)"
output_dir="${repository_root}/dist"
release_version=""
workspace=""

usage() {
  cat <<'USAGE'
Usage: package-release.sh [--release-version VERSION] [--output-dir DIRECTORY]

Build a Cabanon Debian 13 release bundle from the current Git commit.
USAGE
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

log() {
  printf '%s\n' "==> $*" >&2
}

cleanup() {
  if [[ -n "${workspace}" && -d "${workspace}" ]]; then
    rm -rf "${workspace}"
  fi
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --release-version)
      (($# >= 2)) || fail "--release-version requires a value."
      release_version="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || fail "--output-dir requires a directory."
      output_dir="$2"
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

for required_command in git gleam tar sha256sum find sort xargs date; do
  command -v "${required_command}" >/dev/null 2>&1 \
    || fail "Required command is unavailable: ${required_command}"
done

cd "${repository_root}"
git_commit="$(git rev-parse HEAD)"
if [[ -z "${release_version}" ]]; then
  release_version="main-$(git rev-parse --short=12 HEAD)"
fi
[[ "${release_version}" =~ ^[A-Za-z0-9._-]+$ ]] \
  || fail "Release version contains unsafe characters."

mkdir -p "${output_dir}"
output_dir="$(cd -P "${output_dir}" && pwd)"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/cabanon-release.XXXXXX")"
bundle_name="cabanon-release-${release_version}"
bundle_dir="${workspace}/${bundle_name}"
archive_path="${output_dir}/${bundle_name}.tar.gz"

log "Building the Erlang shipment."
"${repository_root}/scripts/package.sh"
[[ -f "${repository_root}/dist/cabanon-erlang-shipment.tar.gz" ]] \
  || fail "Erlang shipment archive was not created."
[[ -f "${repository_root}/dist/cabanon-erlang-shipment.tar.gz.sha256" ]] \
  || fail "Erlang shipment checksum was not created."

mkdir -p "${bundle_dir}/systemd" "${bundle_dir}/installer"
cp "${repository_root}/dist/cabanon-erlang-shipment.tar.gz" "${bundle_dir}/"
cp "${repository_root}/dist/cabanon-erlang-shipment.tar.gz.sha256" "${bundle_dir}/"
cp -a "${repository_root}/priv/migrations" "${bundle_dir}/migrations"
cp "${repository_root}/infra/systemd/cabanon.service" "${bundle_dir}/systemd/cabanon.service"
cp -a "${repository_root}/infra/installer/." "${bundle_dir}/installer/"

frontend_build_dir="${repository_root}/client/build/release-frontend"
rm -rf "${frontend_build_dir}"

log "Building the production frontend."
(
  cd "${repository_root}/client"
  gleam run -m lustre/dev build cabanon_frontend --outdir=build/release-frontend
)
[[ -f "${frontend_build_dir}/index.html" ]] \
  || fail "Production frontend build did not produce index.html."
cp -a "${frontend_build_dir}" "${bundle_dir}/frontend"

built_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat >"${bundle_dir}/manifest.json" <<MANIFEST
{
  "release_version": "${release_version}",
  "git_commit": "${git_commit}",
  "built_at_utc": "${built_at_utc}",
  "target_os": "debian-13",
  "erlang_otp_major": 27,
  "erlang_otp_version": "27.3.4.1"
}
MANIFEST

cat >"${bundle_dir}/frontend/version.json" <<VERSION
{
  "release_version": "${release_version}",
  "git_commit": "${git_commit}",
  "built_at_utc": "${built_at_utc}"
}
VERSION

(
  cd "${bundle_dir}"
  find . -type f ! -name checksums.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > checksums.sha256
)

tar -C "${workspace}" -czf "${archive_path}" "${bundle_name}"
log "Created ${archive_path}"
