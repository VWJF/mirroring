#!/usr/bin/env bash
# feat/Foo  ->  branch-feat-foo
set -euo pipefail

name="${1:?usage: branch-image-tag.sh <branch>}"
name="${name#refs/heads/}"
name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
echo "branch-${name//\//-}"
