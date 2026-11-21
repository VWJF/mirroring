# Developer guide

How to publish the GHCR **image**, pin `action.yml`, tag the **Action**, and run remote tests. Caller setup (credentials, GitHub/GitLab config, inputs) is in [README.md](README.md). Design questions are in [FAQ.md](FAQ.md).

Until these workflows exist on the default branch, **Run workflow** in the Actions UI 404s. Use `gh workflow run … --ref <branch>` or push an `image/v…` tag (Publish uses the workflow files **on that tag**, not branch HEAD). Re-running a failed tag job does not pick up later Promote fixes; move or retag `image/v…` onto a commit that has them.

`ghcr.io/vwjf/mirroring` must be **public**. Callers pull `docker://` with no registry login. Do not dispatch-rebuild a GHCR version that an Action release already pins; bump `image/v…` instead.

## Publishing a release

The GHCR **image** and the **Action** are separate artifacts. An image tag publishes a container and does not change callers. An Action tag is created only after `action.yml` pins an image that is already in GHCR. Existing tags `0.0.1-alpha` through `0.0.5-alpha` stay where they are. Do not move a released Action tag.

### Test a feature branch

1. Push the branch. [Publish image](.github/workflows/publish.yml) pushes `ghcr.io/vwjf/mirroring:sha-<commit>` and `branch-<name>` (`/` in the branch name becomes `-`, lowercased). It does **not** pin `action.yml`.
2. Pin an image on **this branch** (the main contents check is skipped): Actions → **Promote image** on the branch, leave `version` empty for `branch-<name>`, or pass the GHCR version after tagging `image/v…` from this commit (`gh workflow run promote.yml --ref <branch> -f version=0.1.0-alpha.1`).
3. Point the **caller** workflow at the branch (`uses: VWJF/mirroring@<branch>`). `SOURCE_BRANCH` in `./tests/run.sh` is the caller branch that already has that workflow file; it does not select the Action ref.
4. Wait until Publish image is green, then run `./tests/run.sh`.

CI fails pull requests into the default branch if `action.yml` still pins `branch-*` or `sha-*`. After merge, a push to the default branch checks that the pin’s `image/v…` sources match `main` (skipped if that git tag does not exist yet).

### Release an image

1. From the commit you want in GHCR, create an annotated tag `image/vX.Y.Z` or `image/vX.Y.Z-alpha.1` and push it. That commit can be on a feature branch or on the default branch. Plain `v*.*.*` Action tags do **not** publish an image.
2. Wait for Publish image. That pushes `ghcr.io/vwjf/mirroring:<version>` and `v<version>`. A stable version also gets major and minor tags (`v1`, `v1.0`). `latest` is not pushed.
3. [Promote image](.github/workflows/promote.yml) pins `action.yml` to that exact GHCR tag (`0.1.0`, not `v0.1.0`, not `1`) and does **not** create an Action tag or GitHub Release. If the tag is the default-branch tip, it opens a pin PR and requires the image files to match `main`. Otherwise it commits the pin on the unique feature branch **from the tagged commit** (not the branch tip). You can also run Promote yourself (`gh workflow run promote.yml --ref <branch> -f version=0.1.0-alpha.1`). If the branch moved past the tag, retag from the tip or run Promote on that branch.

```bash
git tag -a image/v0.1.0-alpha.1 -m "image/v0.1.0-alpha.1"
git push origin image/v0.1.0-alpha.1
# wait until Publish image is green and the pin is on the branch
```

### Release the Action

After the pin is on the default branch (and remote tests), create the GitHub Release **from `main`**. That tag is the caller pin. No workflow runs afterward. Do not cut the Action tag from a feature branch.

```bash
gh release create v0.0.6-alpha --generate-notes --prerelease
```

Omit `--prerelease` for a stable `vX.Y.Z`. Add `--target <sha>` if HEAD is not the promotion merge. You do not need a separate `git tag` / `git push`. Callers pin `uses: VWJF/mirroring@v0.0.6-alpha`. Put the `docker://` pin in the notes if you want it there. After `v1.0.0`, move `v1` / `v1.0` by hand if you use floating major tags. Do not move `v1` on this Action’s GitLab mirror while `keep_divergent_refs` is true.

## Tests

Remote tests (updates, GitLab options, then the other direction) are driven from your machine. The Action is not invoked locally; GitHub Actions and GitLab’s native push mirror are the systems under test. See [tests/README.md](tests/README.md) and run `./tests/run.sh`.

[VWJF/temp-mirror](https://github.com/VWJF/temp-mirror) is a sample caller. Its destination is set via `vars.GITLAB_URL` (for example `https://gitlab.rcg.sfu.ca/<user>/<repository>.git`).
