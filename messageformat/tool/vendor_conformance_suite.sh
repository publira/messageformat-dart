#!/usr/bin/env bash
#
# Vendors the MessageFormat Working Group conformance suite at a given tag
# into test/conformance/message-format-wg/.
#
# Usage: tool/vendor_conformance_suite.sh <tag>
#   e.g. tool/vendor_conformance_suite.sh LDML48.2
#
# Only the suite's `test/` directory is copied, together with the repository's
# LICENSE (Unicode License v3). The specification text (`spec/`) is not under
# that license and must never be vendored.
#
# Moving to a new tag is its own Issue. After running this script, update the
# pin and the expected case counts in test/conformance/manifest.dart; `dart
# test` reports every file whose count differs.

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: $0 <tag>" >&2
  exit 64
fi

tag="$1"
repository="https://github.com/unicode-org/message-format-wg"
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${package_dir}/test/conformance/message-format-wg"

# An annotated tag lists its commit as `<tag>^{}`; a lightweight tag lists it
# directly. Prefer the peeled entry when both exist.
refs="$(git ls-remote "${repository}" "refs/tags/${tag}" "refs/tags/${tag}^{}")"
commit="$(awk '$2 ~ /\^\{\}$/ { print $1 }' <<<"${refs}")"
if [[ -z "${commit}" ]]; then
  commit="$(awk '{ print $1 }' <<<"${refs}")"
fi
if [[ -z "${commit}" ]]; then
  echo "error: tag ${tag} not found in ${repository}" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

curl --fail --silent --show-error --location \
  "${repository}/archive/${commit}.tar.gz" |
  tar -xz -C "${workdir}" --strip-components=1

rm -rf "${destination}"
mkdir -p "${destination}"
cp -R "${workdir}/test/." "${destination}/"
cp "${workdir}/LICENSE" "${destination}/LICENSE"

cat >"${destination}/SOURCE" <<SOURCE
The files in this directory, except this one, are copied without modification
from the Unicode MessageFormat Working Group repository: its \`test/\`
directory and its LICENSE. They are licensed under the Unicode License v3
(SPDX-License-Identifier: Unicode-3.0); see LICENSE.

Repository: ${repository}
Tag: ${tag}
Commit: ${commit}
Path: test/

Regenerate with: tool/vendor_conformance_suite.sh ${tag}
SOURCE

echo "Vendored ${repository} test/ at ${tag} (${commit})."
