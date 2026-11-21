#!/usr/bin/env bash
# Fail unless the image files are the same at both git refs.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

a="${1:?usage: image-contents-match.sh <ref-a> <ref-b>}"
b="${2:?}"
files=(Dockerfile entrypoint.sh src/mirror.sh src/askpass.sh)

if git diff --quiet "$a" "$b" -- "${files[@]}"; then
  echo "Image contents match: $a and $b"
  exit 0
fi

die "Image contents differ ($a vs $b). Retag image/v* from this branch and publish again."
