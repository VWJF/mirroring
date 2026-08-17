#!/usr/bin/env python3
"""Pin the composite Action's Mirror ref step to a prebuilt GHCR image.

Replaces the active Mirror ref step in root action.yml with:

    uses: docker://ghcr.io/<owner>/<name>:<tag>

Keeps skip-actor and checkout. Writes a commented runner-bash mirror.sh
alternative. Does not move git tags or publish images.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

MIRROR_STEP_NAME = "- name: Mirror ref to GitLab"

# IMAGE_PLACEHOLDER is replaced after the literal composite expressions.
BLOCK_TEMPLATE = """    # Runner-bash (no Docker): run: bash "${{ github.action_path }}/scripts/mirror.sh"
    - name: Mirror ref to GitLab
      if: steps.skip_actor.outputs.skip != 'true'
      uses: docker://IMAGE_PLACEHOLDER
      env:
        GITLAB_URL: ${{ inputs.gitlab_url }}
        GITLAB_USERNAME: ${{ inputs.gitlab_username }}
        GITLAB_TOKEN: ${{ inputs.gitlab_token }}
        GH_TOKEN: ${{ inputs.github_token }}
        GITHUB_TOKEN: ${{ inputs.github_token }}
        ONLY_PROTECTED_BRANCHES: ${{ inputs.only_protected_branches }}
        KEEP_DIVERGENT_REFS: ${{ inputs.keep_divergent_refs }}
        ACTION_PATH: /opt/mirroring
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        required=True,
        help="Image reference without docker:// (e.g. ghcr.io/vwjf/mirroring:0.0.3-alpha)",
    )
    parser.add_argument(
        "--file",
        default="action.yml",
        type=pathlib.Path,
        help="Path to the composite action.yml",
    )
    return parser.parse_args()


def find_mirror_span(lines: list[str]) -> tuple[int, int]:
    idx = next(
        (
            i
            for i, line in enumerate(lines)
            if line.lstrip().startswith(MIRROR_STEP_NAME)
        ),
        None,
    )
    if idx is None:
        raise SystemExit(
            "action.yml has no mirror step to patch "
            "(expected '- name: Mirror ref to GitLab')"
        )

    start = idx
    while start > 0 and lines[start - 1].strip().startswith("#"):
        start -= 1

    end = len(lines)
    for j in range(idx + 1, len(lines)):
        if re.match(r"^    - name:", lines[j]):
            end = j
            break
    return start, end


def render_block(image: str) -> str:
    return BLOCK_TEMPLATE.replace("IMAGE_PLACEHOLDER", image)


def already_pinned(text: str, image: str) -> bool:
    needle = f"uses: docker://{image}"
    return any(line.strip() == needle for line in text.splitlines())


def main() -> int:
    args = parse_args()
    image = args.image.strip()
    if image.startswith("docker://"):
        image = image[len("docker://") :]
    if ":" not in image or image.startswith(":"):
        raise SystemExit(f"invalid image reference: {image}")

    path: pathlib.Path = args.file
    text = path.read_text()
    if already_pinned(text, image):
        print(f"already bumped: uses: docker://{image}")
        return 0

    lines = text.splitlines(keepends=True)
    start, end = find_mirror_span(lines)
    new_text = "".join(lines[:start]) + render_block(image) + "".join(lines[end:])
    if text.endswith("\n") and not new_text.endswith("\n"):
        new_text += "\n"
    path.write_text(new_text)
    print(f"pinned Mirror ref step to docker://{image}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
