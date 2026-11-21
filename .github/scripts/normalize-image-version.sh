#!/usr/bin/env bash
# image/v1.2.3  or  v1.2.3  or  1.2.3  ->  1.2.3
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

raw="${1:?usage: normalize-image-version.sh <image/vX.Y.Z or X.Y.Z>}"
raw="${raw#refs/tags/}"
raw="${raw#image/}"
raw="${raw#v}"

[[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
  die "Invalid image version '$raw' (want 0.1.0 or 0.1.0-alpha.1)"

echo "$raw"
