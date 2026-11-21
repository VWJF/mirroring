#!/usr/bin/env bash
# Sourced by the other scripts in this directory.

die() {
  echo "::error::$*" >&2
  exit 1
}

# ghcr.io/owner/repo in lowercase. Needs GITHUB_REPOSITORY.
image_repo() {
  [[ -n "${GITHUB_REPOSITORY-}" ]] || die "GITHUB_REPOSITORY is not set"
  echo "ghcr.io/$(printf '%s' "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
}
