#!/usr/bin/env bash
# Set GITHUB_OUTPUT for Promote image:
#   mode, version, image_git_tag, pin_tag, checkout_ref, pin_start, match_default
#
# A version on the default branch: open a pin PR (and compare image files to main).
# A version on any other branch: commit that pin on that branch (skip the main check).
# No version on a feature branch: commit branch-* on that branch.
# An image/v* tag that is the default-branch tip: pin PR to main.
# Any other image/v* tag: pin the unique feature branch, starting at the tag.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

dir="$(dirname "$0")"
out() { echo "$1=$2" >>"$GITHUB_OUTPUT"; }

[[ -n "${DEFAULT_BRANCH:-}" ]] || die "DEFAULT_BRANCH is not set"

mode=""
version=""
image_git_tag=""
branch_tag=""
pin_tag=""
checkout_ref=""
pin_start=""
match_default=false

# Remote branches that contain a commit, not including origin/HEAD.
branches_containing() {
  git for-each-ref --format='%(refname:short)' --contains="$1" refs/remotes/origin |
    sed 's|^origin/||' | grep -vx HEAD || true
}

pin_version() {
  version="$(bash "$dir/normalize-image-version.sh" "$1")"
  image_git_tag="image/v$version"
  pin_tag="$version"
}

# image/v* tag from Publish: pin main only if the tag is the default-branch
# tip. Otherwise pin the unique feature branch, from the tagged commit.
pin_from_image_tag() {
  # Heads only. fetch --tags clobbers the tag that triggered this run.
  git fetch origin --prune --no-tags
  local tag_commit found="" b default_head
  tag_commit="$(git rev-parse "${image_git_tag}^{commit}" 2>/dev/null || git rev-parse "HEAD^{commit}")"
  default_head="$(git rev-parse "origin/${DEFAULT_BRANCH}")"

  if [[ "$tag_commit" == "$default_head" ]]; then
    mode=promote
    checkout_ref="$DEFAULT_BRANCH"
    match_default=true
    return
  fi

  while IFS= read -r b; do
    [[ -z "$b" || "$b" == "$DEFAULT_BRANCH" ]] && continue
    if [[ -n "$found" && "$found" != "$b" ]]; then
      die "Tag ${image_git_tag} is on multiple branches (${found}, ${b}). Run Promote from the branch to pin."
    fi
    found="$b"
  done < <(branches_containing "$tag_commit")

  [[ -n "$found" ]] || die "Tag ${image_git_tag} is not on a remote branch. Run Promote from the branch to pin."
  mode=pin-branch
  checkout_ref="$found"
  pin_start="$image_git_tag"
}

if [[ -n "${INPUT_VERSION:-}" ]]; then
  pin_version "$INPUT_VERSION"
  if [[ "${REF_TYPE:-}" == branch ]]; then
    checkout_ref="$REF_NAME"
    if [[ "$REF_NAME" == "$DEFAULT_BRANCH" ]]; then
      mode=promote
      match_default=true
    else
      mode=pin-branch
    fi
  else
    pin_from_image_tag
  fi

elif [[ "${EVENT_NAME:-}" == workflow_dispatch && "${REF_TYPE:-}" == branch && "${REF_NAME:-}" != "$DEFAULT_BRANCH" ]]; then
  mode=pin-branch
  branch_tag="$(bash "$dir/branch-image-tag.sh" "$REF_NAME")"
  pin_tag="$branch_tag"
  checkout_ref="$REF_NAME"

else
  die "Give a version to pin, or run on a feature branch with no version to pin branch-*."
fi

out mode "$mode"
out version "$version"
out image_git_tag "$image_git_tag"
out branch_tag "$branch_tag"
out checkout_ref "$checkout_ref"
out pin_start "$pin_start"
out pin_tag "$pin_tag"
out match_default "$match_default"
echo "mode=$mode pin=$pin_tag checkout=$checkout_ref pin_start=${pin_start:-origin/$checkout_ref} match_default=$match_default"
