#!/bin/sh
set -eu

readonly output_dir="dist"
readonly archive_path="${output_dir}/cabanon-erlang-shipment.tar.gz"

rm -rf "${output_dir}"
gleam export erlang-shipment
mkdir -p "${output_dir}"
tar -C build -czf "${archive_path}" erlang-shipment
(
  cd "${output_dir}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum cabanon-erlang-shipment.tar.gz > cabanon-erlang-shipment.tar.gz.sha256
  else
    shasum -a 256 cabanon-erlang-shipment.tar.gz > cabanon-erlang-shipment.tar.gz.sha256
  fi
)

printf '%s\n' "Created ${archive_path}"
