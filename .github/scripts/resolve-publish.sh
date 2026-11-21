#!/usr/bin/env bash
# Set GITHUB_OUTPUT for Publish image: kind, version, major, minor, stable, branch_tag.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

dir="$(dirname "$0")"
out() { echo "$1=$2" >>"$GITHUB_OUTPUT"; }

parse_version() {
  version="$(bash "$dir/normalize-image-version.sh" "$1")"
  major="${version%%.*}"
  rest="${version#*.}"
  minor="${rest%%.*}"
  if [[ "$version" == *-* ]]; then
    stable=false
  else
    stable=true
  fi
}

kind=""
version=""
major=""
minor=""
stable=false
branch_tag=""

if [[ "${EVENT_NAME:-}" == workflow_dispatch ]]; then
  [[ "${REF_TYPE:-}" == branch && "${REF_NAME:-}" == "${DEFAULT_BRANCH:-}" ]] ||
    die "Rebuild from the default branch only (got ${REF_TYPE-}/${REF_NAME-}). Feature branches publish sha-* and branch-* on push."
  kind=rebuild
  parse_version "$DISPATCH_VERSION"
  echo "Rebuild $version (no promotion)"

elif [[ "${REF_TYPE:-}" == tag ]]; then
  kind=release
  parse_version "$REF_NAME"
  echo "Release $version from $REF_NAME"

elif [[ "${REF_TYPE:-}" == branch ]]; then
  kind=branch
  if [[ -n "${DEFAULT_BRANCH:-}" && "${REF_NAME:-}" != "$DEFAULT_BRANCH" ]]; then
    branch_tag="$(bash "$dir/branch-image-tag.sh" "$REF_NAME")"
    echo "Branch tags sha-* and $branch_tag"
  else
    echo "Default branch: sha-* only"
  fi

else
  die "Unsupported publish event (${EVENT_NAME-} ${REF_TYPE-})"
fi

out kind "$kind"
out version "$version"
out major "$major"
out minor "$minor"
out stable "$stable"
out branch_tag "$branch_tag"
