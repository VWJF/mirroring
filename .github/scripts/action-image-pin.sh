#!/usr/bin/env bash
# Read or replace the docker:// pin in action.yml.
#   action-image-pin.sh get [action.yml]
#   action-image-pin.sh set <tag> [action.yml]
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

cmd="${1:?usage: action-image-pin.sh get|set ...}"
prefix="uses: docker://$(image_repo):"

get_tag() {
  local file="$1" line
  line="$(grep -F "$prefix" "$file" || true)"
  [[ -n "$line" ]] || die "$file has no $prefix pin"
  echo "${line##*:}"
}

case "$cmd" in
  get)
    get_tag "${2:-action.yml}"
    ;;
  set)
    tag="${2:?usage: action-image-pin.sh set <tag> [action.yml]}"
    file="${3:-action.yml}"
    [[ "$tag" != */* && "$tag" != *[[:space:]]* ]] || die "Bad image tag '$tag'"
    current="$(get_tag "$file")"
    if [[ "$current" == "$tag" ]]; then
      echo "already pinned to docker://$(image_repo):$tag"
      exit 0
    fi
    tmp="$(mktemp)"
    sed -E "s|(${prefix})[^[:space:]]+|\\1${tag}|" "$file" >"$tmp"
    mv "$tmp" "$file"
    grep -Fq "${prefix}${tag}" "$file" || die "Failed to pin $tag in $file"
    echo "pinned docker://$(image_repo):$tag"
    ;;
  *)
    die "usage: action-image-pin.sh get|set ..."
    ;;
esac
