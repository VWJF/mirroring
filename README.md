# GitHub → GitLab push-mirror Action

Reusable composite Action ([VWJF/mirroring](https://github.com/VWJF/mirroring)) that **push-mirrors a GitHub ref to GitLab**, using the same knobs and deletion rules as [GitLab push mirroring](https://docs.gitlab.com/user/project/repository/mirror/push/).

- **Standalone:** GitHub → GitLab only. GitLab’s native mirror is not required.
- **Bidirectional:** this Action plus GitLab’s native push mirror (GitLab → GitHub). Native GitLab pull/bidirectional mirroring is not used.

Callers use `uses: VWJF/mirroring@main` (or a tag/SHA). Set `GITLAB_URL` to the destination clone URL (for example `https://gitlab.rcg.sfu.ca/<user>/temp-mirror.git`). Do not hardcode a destination in the Action.

See [FAQ.md](FAQ.md) for design choices, loops, divergence, merges, and recovery.

## What is mirrored

Identical **git trees**: commits, the triggering branch or tag, and tag creates/updates.

Not mirrored: issues, pull requests / merge requests, branch protection, secrets, webhooks, or GitHub/GitLab release objects (git tags still sync). `.github/workflows` and `.gitlab-ci.yml` both exist on both remotes; each platform ignores the other’s CI files.

The Action never runs `git push --mirror`. It only updates the **event’s ref**.

This Action lives in its own repository, so `actions/checkout` of the **source** repo cannot delete `action.yml` / `scripts/` (`github.action_path` is this repo). It checks out the triggering SHA (or the default branch on delete events), not `main` on every run.

## Inputs

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `gitlab_url` | yes | — | HTTPS clone URL of the GitLab destination |
| `gitlab_username` | no | `oauth2` | HTTPS username (typical for a PAT) |
| `gitlab_token` | yes | — | Token with `write_repository`, allowed to push protected branches |
| `github_token` | no | `github.token` | Clone GitHub if private; query branch protection |
| `only_protected_branches` | no | `true` | Skip unprotected GitHub branches (tags still sync) |
| `keep_divergent_refs` | no | `true` | Do not force-push or delete dest-only refs; fail if GitLab diverged |
| `skip_github_actors` | no | empty | Skip these GitHub usernames / `app[bot]` actors (bidirectional loop guard) |

GitLab’s native default for keep-divergent is **overwrite** (`false`). This Action defaults to `true` because bidirectional use must not clobber the other side. Set `keep_divergent_refs: false` to match GitLab’s overwrite behavior for a one-way GitHub → GitLab mirror.

## Standalone setup (GitHub → GitLab)

1. In the **source** GitHub repo, add a workflow that checks out that repo, then calls this Action (`uses: VWJF/mirroring@main`).
2. Add repository secret `GITLAB_TOKEN` (GitLab PAT / project token with `write_repository`).
3. Set repository variable `GITLAB_URL` (HTTPS clone URL). Optionally:
   - `GITLAB_USERNAME` (default `oauth2`)
   - `ONLY_PROTECTED_BRANCHES` (`true`/`false`)
   - `KEEP_DIVERGENT_REFS` (`true`/`false`)
   - `SKIP_GITHUB_ACTORS` (leave empty for standalone)
4. Protect the branches you want mirrored on GitHub (and on GitLab if you use GitLab protection). Keep the two lists in sync.
5. Use **HTTPS** for GitLab (LFS over SSH is not supported by GitLab push mirroring). Both remotes must use the same object format (SHA-1 vs SHA-256). The Action never writes a credential helper or token to the runner’s `~/.gitconfig` (same behavior on GitHub-hosted and self-hosted runners).

## Bidirectional setup

GitHub → GitLab is this Action (near-immediate). GitLab → GitHub is GitLab’s native push mirror (Sidekiq: within ~5 minutes, or ~1 minute if only protected branches). Do not delay this Action to “match” GitLab; it compares **live GitLab** with `git ls-remote`.

1. Complete standalone setup above.
2. Create a **dedicated GitHub user or GitHub App** used only as GitLab’s push-mirror credentials. Do not use a human account that also pushes real work.
3. On GitLab: **Settings → Repository → Mirroring repositories**
   - Direction: **Push**
   - URL: `https://github.com/<owner>/<repo>.git`
   - Username: the dedicated GitHub account
   - Password: a GitHub PAT with **Contents: read/write**. If the repo contains `.github/workflows`, also grant **Workflows: read/write**.
   - Enable **Keep divergent refs**
   - Enable **Only mirror protected branches** if that matches the Action
4. Set GitHub Actions variable `SKIP_GITHUB_ACTORS` to that dedicated username (or `your-app[bot]`).
5. Set `KEEP_DIVERGENT_REFS` to `true` on the Action (default) **and** on GitLab.
6. Protect `main` (and any other mirrored targets) on **both** remotes. Do not rewrite mirrored history.

Loop safety is both:

- skip pushes whose `github.actor` is in `skip_github_actors`
- no-op if GitLab already has the same SHA

### After a divergence

If the same branch (including a merge to `main`) moved on both sides, a non-fast-forward is expected. With `keep_divergent_refs: true` the job fails and **neither history is overwritten**.

Recovery (manual; the Action does not merge for you):

1. Fetch both remotes.
2. Integrate the two tips (merge or rebase) until they share one tip.
3. Push that tip to **one** remote only.
4. Let mirroring copy it to the other.
5. Close leftover PRs/MRs on the other platform. Do not merge the same feature independently on both sides.

Squash/rebase merges are often **not** git-ancestors of the default branch, so a deleted GitHub feature branch may be **left** on GitLab (same as GitLab’s own push mirror).

## Caller example

```yaml
name: Push mirror to GitLab
on:
  push:
  create:
  workflow_dispatch:
    inputs:
      ref:
        description: Branch or tag to mirror
        required: false
        type: string

concurrency:
  group: push-mirror-${{ github.repository }}-${{ github.event.inputs.ref || github.ref }}
  cancel-in-progress: false

jobs:
  mirror:
    if: github.event_name != 'create' || github.event.ref_type == 'tag'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
          fetch-tags: true
          lfs: true
      - uses: VWJF/mirroring@main
        with:
          gitlab_url: ${{ vars.GITLAB_URL }}
          gitlab_username: ${{ vars.GITLAB_USERNAME || 'oauth2' }}
          gitlab_token: ${{ secrets.GITLAB_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          only_protected_branches: ${{ vars.ONLY_PROTECTED_BRANCHES || 'true' }}
          keep_divergent_refs: ${{ vars.KEEP_DIVERGENT_REFS || 'true' }}
          skip_github_actors: ${{ vars.SKIP_GITHUB_ACTORS }}
```

`cancel-in-progress` must stay **false** so an in-flight `git push` is not aborted.

The first checkout is optional if you rely on this Action’s inner checkout of `github.sha`. Keeping it is fine and makes the source tree available to later steps.

## Test pair

[VWJF/temp-mirror](https://github.com/VWJF/temp-mirror) is a sample caller. Its destination is set via `vars.GITLAB_URL` (for example `https://gitlab.rcg.sfu.ca/<user>/temp-mirror.git`).
# mirroring
