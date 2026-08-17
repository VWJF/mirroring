#!/usr/bin/env bash
# Docker Action entrypoint: exec mirror.sh with ACTION_PATH inside the image.
set -euo pipefail
export ACTION_PATH="${ACTION_PATH:-/opt/mirroring}"
exec bash "${ACTION_PATH}/src/mirror.sh" "$@"
