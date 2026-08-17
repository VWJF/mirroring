#!/usr/bin/env bash
# Shared helpers for tests/run.sh. Credentials from `gh` / `glab` logins
# (public and private repos use the same path). Do not run mirror.sh here.
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
pass() { PASSED=$((PASSED + 1)); log "PASS $*"; }
skip() { SKIPPED=$((SKIPPED + 1)); log "SKIP $*"; }
assert_eq() { [[ "$2" == "$3" ]] || die "$1: got '${2:-<none>}', expected '$3'."; }

gh_git() {
  command git \
    -c credential.helper= \
    -c credential.helper='!gh auth git-credential' \
    "$@"
}
gl_git() {
  command git \
    -c credential.helper= \
    -c "credential.https://${GITLAB_HOST}.username=${GITLAB_USERNAME}" \
    -c "credential.https://${GITLAB_HOST}.helper=!f() { echo \"password=\${GITLAB_TOKEN}\"; }; f" \
    "$@"
}

# Peel annotated tags so comparisons use the commit SHA.
_sha() {
  local cmd="$1" remote="$2" spec="$3" sha peeled
  sha="$("$cmd" -C "$WORKDIR" ls-remote --quiet "$remote" "$spec" 2>/dev/null | awk '{print $1; exit}')"
  if [[ -n "$sha" && "$spec" == refs/tags/* ]]; then
    peeled="$("$cmd" -C "$WORKDIR" ls-remote --quiet "$remote" "${spec}^{}" 2>/dev/null | awk '{print $1; exit}')"
    [[ -n "$peeled" ]] && sha="$peeled"
  fi
  printf '%s' "$sha"
}
github_sha() { _sha gh_git origin "$1"; }
gitlab_sha() { _sha gl_git gitlab "$1"; }

commit_push() {
  local side="$1" msg="$2" file="$3" body="$4" branch="${5:-$TEST_BRANCH}"
  git -C "$WORKDIR" checkout -B "$branch" >/dev/null 2>&1
  printf '%s\n' "$body" >"${WORKDIR}/${file}"
  git -C "$WORKDIR" add "$file"
  git -C "$WORKDIR" commit -m "$msg" >/dev/null
  if [[ "$side" == github ]]; then
    gh_git -C "$WORKDIR" push -u origin "HEAD:refs/heads/${branch}" >/dev/null 2>&1
  else
    gl_git -C "$WORKDIR" push gitlab "HEAD:refs/heads/${branch}" >/dev/null
  fi
  git -C "$WORKDIR" rev-parse HEAD
}

# Wait for a new Actions run and watch it. Empty SHA = any new run (deletes).
wait_run() {
  local want="${1:-}" id sha
  local until=$((SECONDS + WAIT))
  log "Waiting for Action${want:+ (${want:0:12})}…"
  while (( SECONDS < until )); do
    while IFS=$'\t' read -r id sha; do
      [[ -z "$id" ]] && continue
      grep -qx "$id" "$KNOWN" 2>/dev/null && continue
      [[ -n "$want" && "$sha" != "$want" ]] && continue
      echo "$id" >>"$KNOWN"
      log "Run ${id}: $(gh run view "$id" --repo "$GITHUB_REPO" --json url --jq .url)"
      gh run watch "$id" --repo "$GITHUB_REPO" >/dev/null || true
      sleep 2
      __log_id=""
      [[ "$(conclusion "$id")" == skipped ]] && continue
      echo "$id"
      return 0
    done < <(gh run list --repo "$GITHUB_REPO" --workflow "$WORKFLOW" --limit 30 \
      --json databaseId,headSha --jq '.[] | [.databaseId, .headSha] | @tsv')
    sleep "$POLL"
  done
  return 1
}

need_run() { wait_run "$1" || die "No Action run: $2"; }
conclusion() { gh run view "$1" --repo "$GITHUB_REPO" --json conclusion --jq .conclusion; }
fetch_log() {
  local i
  if [[ "${__log_id:-}" == "$1" ]]; then
    printf '%s' "${__log:-}"
    return 0
  fi
  __log=""
  for i in 1 2 3 4 5 6 7 8; do
    __log="$(gh run view "$1" --repo "$GITHUB_REPO" --log 2>/dev/null || true)"
    [[ "$__log" == *"Event="* || "$__log" == *"already at"* || "$__log" == *"has diverged"* ]] && break
    sleep 2
  done
  __log_id="$1"
  printf '%s' "$__log"
}
log_has() { fetch_log "$1" | grep -F -q "$2"; }
require_success() {
  [[ "$(conclusion "$1")" == success ]] || die "$2: run $1 was $(conclusion "$1") (expected success)."
}
require_push() {
  require_success "$1" "$2"
  log_has "$1" "only_protected_branches is true and this branch is not protected" \
    && die "$2: skipped as unprotected. Set ONLY_PROTECTED_BRANCHES=false."
  if log_has "$1" "already at" || log_has "$1" "No-op"; then
    die "$2: no-op; expected a real push."
  fi
  log_has "$1" "Updated GitLab" || log_has "$1" "Creating GitLab" || log_has "$1" "Pushing" \
    || die "$2: log did not show a GitLab push."
}

# GitLab native mirror is delayed; poll GitHub until it matches.
wait_github() {
  local spec="$1" want="$2" got="" until=$((SECONDS + MIRROR_WAIT))
  log "Waiting up to ${MIRROR_WAIT}s for GitHub ${spec} → ${want:0:12}…"
  while (( SECONDS < until )); do
    got="$(github_sha "$spec" || true)"
    [[ "$got" == "$want" ]] && return 0
    sleep "$POLL"
  done
  die "GitLab native mirror did not update GitHub to ${want}."
}

setup() {
  # Defaults: caller repo, Action workflow name, GitLab git username, timeouts.
  GITHUB_HOST="${GITHUB_HOST:-github.com}"
  GITHUB_REPO="${GITHUB_REPO:-VWJF/temp-mirror}"
  WORKFLOW="${WORKFLOW_NAME:-Push mirror to GitLab}"
  GITLAB_USERNAME="${GITLAB_USERNAME:-oauth2}"
  WAIT="${RUN_APPEAR_SECONDS:-180}"
  POLL="${POLL_SECONDS:-5}"
  MIRROR_WAIT="${GITLAB_MIRROR_SECONDS:-360}"
  PASSED=0 SKIPPED=0 FF_SHA="" LAST_RUN="" SYNC_SHA=""

  # Tools and GitHub login. Tests push via gh; they do not run mirror.sh.
  command -v git >/dev/null && command -v gh >/dev/null && command -v glab >/dev/null && command -v jq >/dev/null \
    || die "Need git, gh, glab, and jq."
  gh auth status --hostname "$GITHUB_HOST" >/dev/null 2>&1 \
    || die "gh is not logged in: gh auth login --hostname ${GITHUB_HOST}"
  GH_TOKEN="$(gh auth token --hostname "$GITHUB_HOST")"
  [[ -n "$GH_TOKEN" ]] || die "gh auth token was empty."
  [[ "$(gh api --hostname "$GITHUB_HOST" "repos/${GITHUB_REPO}" --jq '.permissions.push // false')" == true ]] \
    || die "gh cannot push to ${GITHUB_REPO}."

  # GitLab URL from env or the caller's Actions variable; strip embedded user:pass.
  GITLAB_URL="${GITLAB_URL:-$(gh variable get GITLAB_URL --repo "$GITHUB_REPO" 2>/dev/null || true)}"
  GITLAB_URL="$(printf '%s' "${GITLAB_URL:-}" | sed -E 's#(https?://)[^/@]+@#\1#')"
  [[ -n "$GITLAB_URL" ]] || die "Set GITLAB_URL (or the GitHub Actions variable of that name)."
  GITLAB_HOST="${GITLAB_HOST:-$(printf '%s' "$GITLAB_URL" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' | cut -d/ -f1 | cut -d@ -f2)}"
  glab auth status --hostname "$GITLAB_HOST" >/dev/null 2>&1 \
    || die "glab is not logged in: glab auth login --hostname ${GITLAB_HOST}"
  GITLAB_TOKEN="${GITLAB_TOKEN:-$(glab config get token --host "$GITLAB_HOST" 2>/dev/null || true)}"
  [[ -n "$GITLAB_TOKEN" ]] || die "Could not read a GitLab token from glab."
  export GIT_TERMINAL_PROMPT=0 GITLAB_TOKEN GITLAB_USERNAME GH_TOKEN

  # Branch that already has push-mirror.yml; knobs from Actions variables.
  SOURCE_BRANCH="${SOURCE_BRANCH:-$(gh repo view "$GITHUB_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)}"
  DEFAULT_BRANCH="$(gh repo view "$GITHUB_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
  SKIP_ACTORS="$(gh variable get SKIP_GITHUB_ACTORS --repo "$GITHUB_REPO" 2>/dev/null || true)"
  KEEP_DIVERGENT="$(gh variable get KEEP_DIVERGENT_REFS --repo "$GITHUB_REPO" 2>/dev/null || echo true)"
  gh api --hostname "$GITHUB_HOST" --method GET \
    "repos/${GITHUB_REPO}/contents/.github/workflows/${WORKFLOW_FILE:-push-mirror.yml}" \
    -f ref="$SOURCE_BRANCH" --jq .path >/dev/null 2>&1 \
    || die "No caller workflow on ${GITHUB_REPO}@${SOURCE_BRANCH}. Set SOURCE_BRANCH."

  # Disposable worktree and refs; cleanup deletes them on both remotes.
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/mirroring-e2e.XXXXXX")"
  KNOWN="$(mktemp)"
  TEST_BRANCH="e2e/mirror-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TEST_TAG="e2e-mirror-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  trap cleanup EXIT

  log "Caller ${GITHUB_REPO} @ ${SOURCE_BRANCH}"
  gh repo clone "$GITHUB_REPO" "$WORKDIR" -- --branch "$SOURCE_BRANCH" --single-branch >/dev/null
  git -C "$WORKDIR" config user.email "mirroring-e2e@localhost"
  git -C "$WORKDIR" config user.name "mirroring-e2e"
  git -C "$WORKDIR" remote add gitlab "$GITLAB_URL"
  gl_git -C "$WORKDIR" ls-remote --quiet gitlab HEAD >/dev/null \
    || die "Cannot read ${GITLAB_URL} with glab credentials."
}

cleanup() {
  local st=$? b
  if [[ "${KEEP_TEST_REFS:-}" != 1 && -n "${WORKDIR:-}" && -d "${WORKDIR:-}" ]]; then
    for b in "$TEST_BRANCH" "${TEST_BRANCH}-unmerged" "${TEST_BRANCH}-merged"; do
      gh_git -C "$WORKDIR" push origin --delete "refs/heads/${b}" >/dev/null 2>&1 || true
      gl_git -C "$WORKDIR" push gitlab --delete "refs/heads/${b}" >/dev/null 2>&1 || true
    done
    gh_git -C "$WORKDIR" push origin --delete "refs/tags/${TEST_TAG}" >/dev/null 2>&1 || true
    gl_git -C "$WORKDIR" push gitlab --delete "refs/tags/${TEST_TAG}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORKDIR:-}" "${KNOWN:-}"
  exit "$st"
}
