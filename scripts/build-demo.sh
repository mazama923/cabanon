#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -P "${script_dir}/.." && pwd)"
output_dir="${repository_root}/client/build/github-pages"
index_file="${output_dir}/index.html"
temporary_index_file="${index_file}.tmp"

rm -rf "${output_dir}"

(
  cd "${repository_root}/client"
  gleam run -m lustre/dev build cabanon_demo --outdir=build/github-pages
)

[[ -f "${index_file}" ]] || {
  printf '%s\n' "ERROR: Demo build did not produce index.html." >&2
  exit 1
}

sed 's|src="/cabanon_demo.js"|src="cabanon_demo.js"|' "${index_file}" \
  >"${temporary_index_file}"
mv "${temporary_index_file}" "${index_file}"
: >"${output_dir}/.nojekyll"
