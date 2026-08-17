#!/usr/bin/env bash
# Build the subdirectory Docker image from this Action checkout and run mirror.sh.
#
# Nested uses: VWJF/mirroring/mirror@${{ github.action_ref }} is invalid: composite
# action.yml cannot use the github context in `uses` (Unrecognized named-value:
# 'github'). github.action_path is valid in `run:` / `env:`.
set -euo pipefail

context="${MIRROR_IMAGE_CONTEXT:?MIRROR_IMAGE_CONTEXT is required}"
[[ -f "${context}/Dockerfile" ]] || {
  printf 'Error: Dockerfile not found in %s\n' "$context" >&2
  exit 1
}

image="${MIRROR_IMAGE_TAG:-mirroring-runtime}"
docker build -t "$image" "$context"

event_path="${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is not set}"
workspace="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"

docker_args=(
  --rm
  -v "${workspace}:/github/workspace"
  -v "${event_path}:/github/workflow/event.json:ro"
  -w /github/workspace
  -e ACTION_PATH=/opt/mirroring
  -e GITHUB_EVENT_PATH=/github/workflow/event.json
  -e GITHUB_WORKSPACE=/github/workspace
)

pass_env=(
  GITLAB_URL
  GITLAB_USERNAME
  GITLAB_TOKEN
  GH_TOKEN
  GITHUB_TOKEN
  ONLY_PROTECTED_BRANCHES
  KEEP_DIVERGENT_REFS
  GITHUB_REPOSITORY
  GITHUB_REF
  GITHUB_SHA
  GITHUB_EVENT_NAME
  GITHUB_ACTOR
  GITHUB_API_URL
  GITHUB_SERVER_URL
  GITHUB_GRAPHQL_URL
  GITHUB_REF_NAME
  GITHUB_REF_TYPE
)

for name in "${pass_env[@]}"; do
  if [[ -n "${!name+x}" ]]; then
    docker_args+=(-e "$name")
  fi
done

docker run "${docker_args[@]}" "$image"
