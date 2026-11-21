#!/usr/bin/env bash
# Print the docker:// pin. With --forbid-test-tags, fail on branch-* / sha-*.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

forbid=false
if [[ "${1-}" == --forbid-test-tags ]]; then
  forbid=true
  shift
fi
file="${1:-action.yml}"

tag="$(bash "$(dirname "$0")/action-image-pin.sh" get "$file")"
echo "action.yml pins docker://$(image_repo):$tag"

if [[ "$forbid" == true && ( "$tag" == branch-* || "$tag" == sha-* ) ]]; then
  die "$file pins :$tag. Default-branch PRs must pin a release image, not branch-* or sha-*."
fi
