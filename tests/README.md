# Remote Action tests

These tests do **not** run `mirror.sh` on your laptop. A local driver mutates remotes and asserts; GitHub Actions (and GitLab native push mirror) remain the systems under test.

They prove **updates** first, then the **GitLab knobs**, then the **other direction**. Creating a disposable GitHub branch and seeing GitLab catch up is only the happy path: that create is **setup for test 1**, not its own numbered test.

The harness is two files: [`run.sh`](run.sh) (the seven tests) and [`helpers.sh`](helpers.sh) (`gh` / `glab` login, git, wait for Actions). Public vs private does not change the command.

## GitHub-driven (Action is the SUT)

Mutate GitHub, then check GitLab. The script does not run `mirror.sh` locally.

### 1. Same branch, second push (fast-forward)

**Driver:** create a disposable test branch from `SOURCE_BRANCH` (the branch that already has the caller workflow) and `git push` it to GitHub. That first push is **setup** so GitLab already has the ref. Then commit **again** on the same branch and push to GitHub (a true fast-forward, not only “create missing ref”).

**Remote:** each push starts the caller workflow; the Action push-mirrors that ref to GitLab.

**Pass:** the second Action run **succeeds** and the log shows a **real push** (`Pushing` / `Updated GitLab`), not a skip and not `already at` / `No-op`. After it, `git ls-remote` GitLab SHA **equals** GitHub SHA. If the log says the branch was skipped because `only_protected_branches` is true, that is a **fail** of the test setup (set `ONLY_PROTECTED_BRANCHES=false` or protect the branch), not a successful skip.

This is the automated form of “I pushed a commit on GitHub and GitLab caught up,” including a real fast-forward.

### 2. Idempotent no-op

**Driver:** `gh run rerun` of the successful fast-forward job (same SHA, no new git push). GitHub has no **Run workflow** / `workflow_dispatch` on a non-default branch, so re-run is the right trigger (as in the manual test).

**Remote:** the Action compares live GitLab with `git ls-remote`. The destination already has that SHA.

**Pass:** the run **succeeds** and **exits 0**. The log says GitLab already has that SHA (`already at` / `No-op`). GitLab SHA is **unchanged**. This is not a no-op unless the log says so; a silent success that pushed again is a fail.

### 3. Tag create, then tag delete

**Driver:** `git tag` (annotated) on the fast-forward commit and `git push` the tag to GitHub. GitLab should get the tag. Then delete the tag on **GitHub only** (`git push origin --delete refs/tags/…`). This is **one** test, not two numbered tests.

**Remote:** a tag push already fires `on: push`. The Action should create/update the tag on GitLab. The caller must **not** also use `on: create` (that caused two Actions runs for one tag in the manual test). On delete, the Action sees the delete. GitLab push-mirror **never prunes tags**.

**Pass:** create run **succeeds**; GitLab has the tag at the same commit (peel annotated tags); **exactly one** workflow run for that tag push (two runs = caller still has `on: create`). Delete run **succeeds** (exits 0 without deleting on GitLab). GitLab **still has** the tag. If GitLab lost the tag, the test fails.

### 4. keep_divergent_refs (Action default is true)

**Driver:** from the same parent, add a commit on **GitLab only** (commit A) and a **different** commit on the same branch on GitHub (commit B). Then wait for the Action that GitHub’s push triggered. Afterward, the driver resets the GitLab branch to the GitHub tip so later tests can run.

**Remote:** `keep_divergent_refs` is true, so the Action must **not** overwrite GitLab.

**Pass:** the Action run **fails** (a red X is the intended result). The log contains `has diverged` and the two SHAs. GitLab still has A; GitHub still has B. A green job that copied B onto GitLab is a **fail** of this test. Do not force-overwrite.

This matches the manual test whose message was: `Error: GitLab ref … has diverged (GitHub=…, GitLab=…). keep_divergent_refs is true, so this Action will not overwrite.`

### 5. Merged vs unmerged branch delete

Only if `keep_divergent_refs` is **false**; with true, dest-only refs are left on purpose.

**Driver:** on throwaway branches, (1) push an **unmerged** commit, delete that branch on GitHub; (2) if `ALLOW_MAIN_TEST=1`, merge another throwaway into the repo default with a real merge commit (git ancestry, **not** a GitHub squash-merge / PR “merged” flag), then delete it on GitHub.

**Remote:** the Action deletes on GitLab only when the deleted tip is an ancestor of the default branch. Squash-merge leftover branches are often **not** ancestors, so GitLab keeps them (same as GitLab’s own push mirror).

**Pass:** unmerged delete → GitLab **keeps** the branch. Merged delete → GitLab **drops** it. If the caller still has `KEEP_DIVERGENT_REFS=true`, **skip** with a clear log. The merged half is skipped without `ALLOW_MAIN_TEST=1` because it pushes a merge to the default branch.

## 6–7: The other direction, then production refs

### 6. Bidirectional (the real product)

Turn on GitLab’s native **push** mirror to GitHub with a **dedicated** GitHub user (or App), set `SKIP_GITHUB_ACTORS` to that user, and enable Keep divergent refs on GitLab.

**Driver:** push a unique commit on **GitLab only**, wait for it on GitHub, and watch the Action. Then push a unique commit on **GitHub only** and wait for GitLab. Then wait `LOOP_SETTLE_SECONDS` to see whether extra Action runs keep firing.

**Remote:** GitLab native push mirror copies GitLab→GitHub (Sidekiq: often ~1–5 minutes). The Action copies GitHub→GitLab (near-immediate). The loop guard is `skip_github_actors` **and** the SHA no-op. Pushes from the Action use a GitLab token, so GitHub’s “GITHUB_TOKEN does not retrigger workflows” does **not** stop this loop by itself.

**Pass:**
- Push on GitLab → appears on GitHub; the GitHub Action **skips** (actor) or **no-ops** (SHA). GitLab is **not overwritten**.
- Push on GitHub → appears on GitLab; GitLab’s mirror does not start a ping-pong of extra commits.
- The Action does **not** run in a tight loop (extra runs, if any, are skip/no-op only).

Skip clearly if native mirror or `SKIP_GITHUB_ACTORS` is not configured.

### 7. main (or another protected branch)

Once you trust the feature branch, push `main` (or another **protected** branch). That is where merge-target divergence hurts. With `only_protected_branches` true this is the path that matters in production.

**Driver:** unique commit on `PROTECTED_BRANCH` if set, otherwise the repo default branch.

**Remote:** the Action push-mirrors that protected ref to GitLab (it must not skip it as unprotected).

**Pass:** Action **succeeds** with a real push; GitLab SHA equals GitHub. **Skip** with a clear log if the chosen branch is not protected. **Skip** (refuse) mutating the repo default / `main` unless `ALLOW_MAIN_TEST=1`. A passing run **leaves that commit** on the protected branch.

## Run

Log in once (`gh auth login`, `glab auth login --hostname <gitlab>`). Tokens come from those CLIs — do not export them. The caller needs the push-mirror workflow on `SOURCE_BRANCH`, Actions enabled, secret `GITLAB_TOKEN`, and variable `GITLAB_URL`. For tests 1–6 on an unprotected `e2e/mirror-*` branch, `ONLY_PROTECTED_BRANCHES=false`.

```bash
export GITHUB_REPO=VWJF/temp-mirror
export SOURCE_BRANCH=feat/github-gitlab-push-mirror   # until the workflow is on main
export GITLAB_URL=https://gitlab.rcg.sfu.ca/isahay/temp-mirror.git
./tests/run.sh          # all seven; 5–7 skip themselves if not set up
./tests/run.sh 1 2      # optional: README numbers only
```

Optional: `ALLOW_MAIN_TEST=1` (test 5 merged-half and test 7 on `main`), `KEEP_TEST_REFS=1`, `PROTECTED_BRANCH=…`.

Disposable refs `e2e/mirror-*` / `e2e-mirror-*` are deleted on both remotes when the script exits.

## Environment variables

Used by [`helpers.sh`](helpers.sh) and [`run.sh`](run.sh). Do not set `SECONDS=` — that is bash’s builtin elapsed-seconds counter, used as the wait clock.

| Variable | Purpose |
|---|---|
| `SECONDS` | Bash builtin (seconds since the shell started). Wait loops use it as a deadline; not an export. |
| `GITHUB_REPO` | Caller GitHub repo (`owner/name`; default `VWJF/temp-mirror`). |
| `SOURCE_BRANCH` | Branch that already has the caller workflow (default: repo default branch). |
| `GITLAB_URL` | GitLab clone URL; if unset, read from the repo Actions variable of the same name. |

**Optional**
| Variable | Purpose |
|---|---|
| `RUN_APPEAR_SECONDS` | How long to wait for a GitHub Actions run to appear (default **180**). |
| `POLL_SECONDS` | Sleep between polls while waiting for runs or GitHub SHAs (default **5**). |
| `GITLAB_MIRROR_SECONDS` | How long to wait for GitLab’s native push mirror to update GitHub (default **360**). |
| `GITHUB_HOST` | Hostname for `gh` (default `github.com`). |
| `GITLAB_HOST` | Hostname for `glab`; default parsed from `GITLAB_URL`. |
| `GITLAB_USERNAME` | Git HTTP username for GitLab (default `oauth2`). |
| `GITLAB_TOKEN` | GitLab token; filled from `glab`, not required to export. |
| `GH_TOKEN` | Filled from `gh auth token`; do not export. |
| `WORKFLOW_NAME` | Actions workflow name to watch (default `Push mirror to GitLab`). |
| `WORKFLOW_FILE` | Caller workflow file under `.github/workflows/` (default `push-mirror.yml`). |
| `KEEP_TEST_REFS` | Set to `1` to leave disposable `e2e/mirror-*` refs on both remotes. |
| `ALLOW_MAIN_TEST` | Set to `1` to allow test 5’s merged-half and test 7 on the default branch. |
| `PROTECTED_BRANCH` | Test 7 target branch (default: repo default branch). |
| `TMPDIR` | Parent directory for the disposable worktree (default `/tmp`). |

The harness also **reads** these GitHub Actions **repository variables** via `gh` (they are not local exports): `SKIP_GITHUB_ACTORS` (test 6 skips if empty) and `KEEP_DIVERGENT_REFS` (test 5 skips unless false). `GIT_TERMINAL_PROMPT=0` is set internally.
