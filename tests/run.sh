#!/usr/bin/env bash
# The seven remote tests. Helpers: tests/helpers.sh  Spec: tests/README.md
# Login: gh auth login   and   glab auth login
# Usage: ./tests/run.sh          # all seven (5–7 skip themselves if not set up)
#        ./tests/run.sh 1 2 3    # by README number
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=helpers.sh
source "${ROOT}/helpers.sh"

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { sed -n '2,6p' "$0"; exit 0; }

# 1. Same branch, second push (fast-forward). First push is setup only.
test_1() {
  log ""; log "== 1. ff =="
  local sha run
  sha="$(commit_push github "e2e: create ${TEST_BRANCH}" .mirroring-e2e create)"
  run="$(need_run "$sha" "setup push")"
  require_success "$run" "setup"
  assert_eq "GitLab after create" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$sha"

  sha="$(commit_push github "e2e: ff ${TEST_BRANCH}" .mirroring-e2e ff)"
  run="$(need_run "$sha" "fast-forward")"
  require_push "$run" "ff"
  assert_eq "GitLab after ff" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$sha"
  FF_SHA="$sha" SYNC_SHA="$sha" LAST_RUN="$run"
  pass "ff ${sha:0:12}"
}

# 2. Re-run the same job; GitLab already has the SHA.
test_2() {
  log ""; log "== 2. noop =="
  [[ -n "$LAST_RUN" ]] || die "test 2 needs test 1 first."
  local before updated st until
  before="$(gitlab_sha "refs/heads/${TEST_BRANCH}")"
  updated="$(gh run view "$LAST_RUN" --repo "$GITHUB_REPO" --json updatedAt --jq .updatedAt)"
  gh run rerun "$LAST_RUN" --repo "$GITHUB_REPO"
  until=$((SECONDS + WAIT))
  while (( SECONDS < until )); do
    st="$(gh run view "$LAST_RUN" --repo "$GITHUB_REPO" --json status --jq .status)"
    [[ "$st" != completed || "$(gh run view "$LAST_RUN" --repo "$GITHUB_REPO" --json updatedAt --jq .updatedAt)" != "$updated" ]] && break
    sleep "$POLL"
  done
  gh run watch "$LAST_RUN" --repo "$GITHUB_REPO" >/dev/null || true
  __log_id=""
  require_success "$LAST_RUN" "noop"
  log_has "$LAST_RUN" "already at" || log_has "$LAST_RUN" "No-op" || die "Re-run was not a SHA no-op."
  assert_eq "GitLab after noop" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$before"
  pass "noop"
}

# 3. Tag create, then delete on GitHub; GitLab keeps the tag.
test_3() {
  log ""; log "== 3. tag create + delete =="
  [[ -n "$FF_SHA" ]] || die "test 3 needs test 1 first."
  local run extra id
  git -C "$WORKDIR" tag -a "$TEST_TAG" "$FF_SHA" -m "e2e $TEST_TAG"
  gh_git -C "$WORKDIR" push origin "refs/tags/${TEST_TAG}" >/dev/null
  run="$(need_run "$FF_SHA" "tag push")"
  require_success "$run" "tag create"
  sleep 25
  extra=0
  while read -r id; do
    grep -qx "$id" "$KNOWN" && continue
    [[ "$(gh run view "$id" --repo "$GITHUB_REPO" --json headSha --jq .headSha)" == "$FF_SHA" ]] || continue
    extra=$((extra + 1)); echo "$id" >>"$KNOWN"
  done < <(gh run list --repo "$GITHUB_REPO" --workflow "$WORKFLOW" --limit 30 --json databaseId --jq '.[].databaseId')
  (( extra == 0 )) || die "Tag push started ${extra} extra run(s). Drop on: create from the caller workflow."
  assert_eq "GitLab tag" "$(gitlab_sha "refs/tags/${TEST_TAG}")" "$FF_SHA"

  gh_git -C "$WORKDIR" push origin --delete "refs/tags/${TEST_TAG}" >/dev/null
  run="$(need_run "" "tag delete")"
  require_success "$run" "tag delete"
  [[ -n "$(gitlab_sha "refs/tags/${TEST_TAG}")" ]] || die "GitLab pruned the tag."
  pass "tag (GitLab still has ${TEST_TAG})"
}

# 4. keep_divergent_refs: GitLab A + GitHub B → Action fails, neither overwritten.
test_4() {
  log ""; log "== 4. diverge =="
  [[ -n "$SYNC_SHA" ]] || die "test 4 needs test 1 first."
  local gl_only gh_only run
  git -C "$WORKDIR" checkout -B "$TEST_BRANCH" "$SYNC_SHA" >/dev/null 2>&1
  gl_only="$(commit_push gitlab "e2e: gitlab-only" .mirroring-e2e-gl gitlab-only)"
  git -C "$WORKDIR" checkout -B "$TEST_BRANCH" "$SYNC_SHA" >/dev/null 2>&1
  gh_only="$(commit_push github "e2e: github-only" .mirroring-e2e-gh github-only)"
  run="$(need_run "$gh_only" "diverge")"
  [[ "$(conclusion "$run")" == failure ]] || die "Diverge run $run was $(conclusion "$run"); expected failure."
  log_has "$run" "has diverged" || die "Failing run did not say has diverged."
  assert_eq "GitLab kept A" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$gl_only"
  assert_eq "GitHub kept B" "$(github_sha "refs/heads/${TEST_BRANCH}")" "$gh_only"
  gl_git -C "$WORKDIR" push --force gitlab "${gh_only}:refs/heads/${TEST_BRANCH}" >/dev/null
  SYNC_SHA="$gh_only"
  pass "diverge (reset GitLab to ${gh_only:0:12})"
}

# 5. Unmerged delete keeps GitLab branch. Merged delete drops it (needs KEEP_DIVERGENT_REFS=false).
test_5() {
  log ""; log "== 5. branch-delete =="
  case "$(printf '%s' "$KEEP_DIVERGENT" | tr '[:upper:]' '[:lower:]')" in
    false|no|0) ;;
    *) skip "branch-delete (KEEP_DIVERGENT_REFS is true; dest-only refs stay)"; return 0 ;;
  esac
  local b="${TEST_BRANCH}-unmerged" sha run
  # Branch from SOURCE_BRANCH so the caller workflow exists (main may not have it yet).
  git -C "$WORKDIR" checkout -B "$b" "$SOURCE_BRANCH" >/dev/null 2>&1
  sha="$(commit_push github "e2e: unmerged $b" .mirroring-e2e-unmerged unmerged "$b")"
  run="$(need_run "$sha" "unmerged create")"
  require_success "$run" "unmerged create"
  gh_git -C "$WORKDIR" push origin --delete "refs/heads/${b}" >/dev/null
  run="$(need_run "" "unmerged delete")"
  require_success "$run" "unmerged delete"
  [[ -n "$(gitlab_sha "refs/heads/${b}")" ]] || die "GitLab dropped an unmerged branch."
  if [[ "${ALLOW_MAIN_TEST:-}" != 1 ]]; then
    pass "branch-delete (unmerged kept; merged half needs ALLOW_MAIN_TEST=1)"
    return 0
  fi
  local mb="${TEST_BRANCH}-merged" merge_sha
  git -C "$WORKDIR" checkout -B "$mb" "$SOURCE_BRANCH" >/dev/null 2>&1
  sha="$(commit_push github "e2e: merged $mb" .mirroring-e2e-merged merged "$mb")"
  need_run "$sha" "merged create" >/dev/null
  git -C "$WORKDIR" checkout -B "$DEFAULT_BRANCH" "$(github_sha "refs/heads/${DEFAULT_BRANCH}")" >/dev/null 2>&1
  git -C "$WORKDIR" merge --no-ff -m "e2e: merge $mb" "$sha" >/dev/null
  merge_sha="$(git -C "$WORKDIR" rev-parse HEAD)"
  gh_git -C "$WORKDIR" push origin "HEAD:refs/heads/${DEFAULT_BRANCH}" >/dev/null
  run="$(need_run "$merge_sha" "merge to ${DEFAULT_BRANCH}")"
  require_success "$run" "merge"
  gh_git -C "$WORKDIR" push origin --delete "refs/heads/${mb}" >/dev/null
  need_run "" "merged delete" >/dev/null
  [[ -z "$(gitlab_sha "refs/heads/${mb}")" ]] || die "GitLab still has merged branch $mb."
  pass "branch-delete (unmerged kept, merged dropped)"
}

# 6. Bidirectional: GitLab native mirror + Action, no loop.
test_6() {
  log ""; log "== 6. bidirectional =="
  if [[ -z "$SKIP_ACTORS" ]]; then
    skip "bidirectional (set SKIP_GITHUB_ACTORS and GitLab native push mirror)"
    return 0
  fi
  [[ -n "$SYNC_SHA" ]] || die "test 6 needs test 1 first."
  local gl_sha gh_sha run how extra id
  git -C "$WORKDIR" checkout -B "$TEST_BRANCH" "$SYNC_SHA" >/dev/null 2>&1
  gl_sha="$(commit_push gitlab "e2e: gl→gh" .mirroring-e2e-gl gl-to-gh)"
  wait_github "refs/heads/${TEST_BRANCH}" "$gl_sha"
  run="$(need_run "$gl_sha" "GitLab→GitHub")"
  require_success "$run" "gl→gh"
  if log_has "$run" "Skipping mirror: github.actor"; then how="skip actor"
  elif log_has "$run" "already at" || log_has "$run" "No-op"; then how="SHA no-op"
  else die "Action after GitLab→GitHub was not skip/no-op."; fi
  assert_eq "GitLab not overwritten" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$gl_sha"

  gh_sha="$(commit_push github "e2e: gh→gl" .mirroring-e2e gh-to-gl)"
  run="$(need_run "$gh_sha" "GitHub→GitLab")"
  require_push "$run" "gh→gl"
  assert_eq "GitLab after GitHub push" "$(gitlab_sha "refs/heads/${TEST_BRANCH}")" "$gh_sha"
  SYNC_SHA="$gh_sha"
  sleep 60
  extra=0
  while read -r id; do
    grep -qx "$id" "$KNOWN" && continue
    extra=$((extra + 1)); echo "$id" >>"$KNOWN"
    gh run watch "$id" --repo "$GITHUB_REPO" >/dev/null || true
    log_has "$id" "Skipping mirror: github.actor" || log_has "$id" "already at" || log_has "$id" "No-op" \
      || die "Extra run $id after sync was not skip/no-op (tight loop)."
  done < <(gh run list --repo "$GITHUB_REPO" --workflow "$WORKFLOW" --limit 30 --json databaseId --jq '.[].databaseId')
  (( extra <= 2 )) || die "Action ran ${extra} extra times after sync."
  pass "bidirectional (${how})"
}

# 7. Protected / main. Refuses to push main unless ALLOW_MAIN_TEST=1.
test_7() {
  log ""; log "== 7. protected =="
  local target="${PROTECTED_BRANCH:-$DEFAULT_BRANCH}" prot sha run
  prot="$(gh api --hostname "$GITHUB_HOST" "repos/${GITHUB_REPO}/branches/${target}" --jq '.protected // false' 2>/dev/null || echo false)"
  [[ "$prot" == true ]] || { skip "protected (${target} is not protected)"; return 0; }
  if [[ "$target" == "$DEFAULT_BRANCH" && "${ALLOW_MAIN_TEST:-}" != 1 ]]; then
    skip "protected (will not push ${target} without ALLOW_MAIN_TEST=1)"
    return 0
  fi
  gh_git -C "$WORKDIR" fetch origin "$target" >/dev/null
  git -C "$WORKDIR" checkout -B "$target" "origin/${target}" >/dev/null 2>&1
  sha="$(commit_push github "e2e: protected $target" .mirroring-e2e-protected "protected $target" "$target")"
  run="$(need_run "$sha" "$target")"
  require_push "$run" "protected"
  assert_eq "GitLab ${target}" "$(gitlab_sha "refs/heads/${target}")" "$sha"
  pass "protected ${target} ${sha:0:12} (commit stays)"
}

setup

# Always run 1–7 unless you pass numbers: ./tests/run.sh 1 2
if [[ $# -eq 0 ]]; then
  set -- 1 2 3 4 5 6 7
fi
need1=false
for n in "$@"; do
  case "$n" in 2|3|4|6) need1=true ;; esac
done
if $need1; then
  seen1=false
  for n in "$@"; do [[ "$n" == 1 ]] && seen1=true; done
  $seen1 || test_1
fi
for n in "$@"; do
  case "$n" in
    1) test_1 ;; 2) test_2 ;; 3) test_3 ;; 4) test_4 ;;
    5) test_5 ;; 6) test_6 ;; 7) test_7 ;;
    *) die "Unknown test '$n'. Use 1–7 (see tests/README.md)." ;;
  esac
done

(( PASSED > 0 )) || die "Nothing passed (${SKIPPED} skipped)."
log ""; log "Done: ${PASSED} passed, ${SKIPPED} skipped."
