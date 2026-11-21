#!/usr/bin/env bash
# Set GITHUB_OUTPUT for Promote image: mode, version, image_git_tag, pin_tag, checkout_ref.
#
# A version means: open a pin PR against the default branch.
# No version on a feature branch means: commit branch-* on that branch.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

dir="$(dirname "$0")"
out() { echo "$1=$2" >>"$GITHUB_OUTPUT"; }

[[ -n "${DEFAULT_BRANCH:-}" ]] || die "DEFAULT_BRANCH is not set"

version=""
image_git_tag=""
branch_tag=""
pin_tag=""
checkout_ref=""

if [[ -n "${INPUT_VERSION:-}" ]]; then
  [[ "${EVENT_NAME:-}" == workflow_dispatch && "${REF_TYPE:-}" == branch && "${REF_NAME:-}" != "$DEFAULT_BRANCH" ]] &&
    die "Do not pass a version on a feature branch. Omit version to pin branch-*, or run Promote from $DEFAULT_BRANCH."
  mode=promote
  version="$(bash "$dir/normalize-image-version.sh" "$INPUT_VERSION")"
  image_git_tag="image/v$version"
  pin_tag="$version"
  checkout_ref="$DEFAULT_BRANCH"

elif [[ "${EVENT_NAME:-}" == workflow_dispatch && "${REF_TYPE:-}" == branch && "${REF_NAME:-}" != "$DEFAULT_BRANCH" ]]; then
  mode=test-pin
  branch_tag="$(bash "$dir/branch-image-tag.sh" "$REF_NAME")"
  pin_tag="$branch_tag"
  checkout_ref="$REF_NAME"

else
  die "Give a version on the default branch (pin PR), or no version on a feature branch (test pin)."
fi

out mode "$mode"
out version "$version"
out image_git_tag "$image_git_tag"
out branch_tag "$branch_tag"
out checkout_ref "$checkout_ref"
out pin_tag "$pin_tag"
echo "mode=$mode pin=$pin_tag checkout=$checkout_ref"
