---
name: deploy-source-guard
description: >
  Pin a deploy that builds from a live working checkout to exactly one commit, and prove the
  running build is that commit. Activates when writing or editing a deploy script (deploy-*.sh,
  release scripts, `vercel deploy` / `modal deploy` / docker compose build wrappers), when a deploy
  shipped code that matches no commit, or when a deploy "succeeded" but the old build kept serving.
---

# Deploy Source Guard

**Principle:** a deploy that builds from a working checkout ships whatever is on disk at each
moment, not a commit. Pin the source before the first stage, re-verify it before every stage, and
refuse to call the deploy done until the running app reports the pinned SHA.

**The one question:** *If someone switches branches or edits a file while this deploy runs, what
ships?* If the answer is "a mix", the script needs this guard.

## When This Skill Activates

- A deploy script builds or uploads from the repo checkout rather than a CI artifact
- A multi-stage deploy (migrate, backend, frontend, workers) runs for minutes
- A post-deploy check prints a WARNING instead of failing
- A deploy runs over SSH with sudo, or against a database it does not migrate

## Decision Tree

```
Does the deploy build from a mutable checkout?
├── NO (immutable CI artifact by digest) → pin the artifact digest instead; stop here
└── YES
    ├── Before stage 1: tree clean (tracked + untracked, not ignored)?  NO → abort
    ├── HEAD == origin/main or a release-* tag?                          NO → abort
    │     (emergency override env var skips THIS check only, never the clean-tree check)
    ├── Record DEPLOY_SOURCE_SHA
    ├── Before EVERY stage: HEAD unchanged and tree still clean?         NO → abort
    ├── Code-only deploy: target schema has pending migrations?          YES → abort
    │     schema AHEAD of commit (rollback)?                              → warn, continue
    │     status unreadable?                                              → abort
    └── After deploy: running app reports DEPLOY_SOURCE_SHA within N s?  NO → exit non-zero
```

## Core Rules

1. **Pin once, before any mutation.** Dry runs skip the pin; real runs never do.
2. **Re-check at every stage boundary.** Hook the check into the function that prints stage
   headers, so a new stage cannot forget it.
3. **The override relaxes provenance, never cleanliness.** An emergency deploy of an unmerged
   commit is sometimes right; shipping uncommitted files is never right.
4. **The deploy's own tools must not dirty the tree.** Run package managers frozen
   (`uv run --frozen`, `bun install --frozen-lockfile`, `npm ci`), or a stale lockfile rewrites
   itself mid-deploy and trips the guard after some stages already shipped.
5. **Drift gates block only on "behind".** Pending migrations or an unreadable status block. A
   database ahead of the commit is the normal state of a rollback: warn. Match the tool's exact
   message text, not just its exit code (many `migrate status` commands exit non-zero for both).
6. **Verification that warns is not verification.** Poll the build-identity endpoint with a
   bounded retry, then exit non-zero on unreachable, placeholder (`dev`), or mismatched SHA.
7. **Long remote deploys outlive credentials and sessions.** Acquire sudo up front and keep it
   alive in a background loop tied to the script's PID; warn when not inside tmux or screen.

## Implementation Pattern

```bash
# scripts/deploy-source-guard.sh  (source it from every deploy script)
deploy_source_fail() { printf '  ✗ %s\n' "$1" >&2; exit 1; }
deploy_source_dirty() { [ -n "$(git status --porcelain --untracked-files=normal)" ]; }

deploy_source_pin() {
  deploy_source_dirty && { git status --short >&2; deploy_source_fail "working tree is not clean"; }
  DEPLOY_SOURCE_SHA="$(git rev-parse HEAD)"
  [ "${DEPLOY_ALLOW_UNPINNED:-0}" = 1 ] && return 0
  git fetch -q origin main --tags || deploy_source_fail "cannot verify source against origin"
  [ "$DEPLOY_SOURCE_SHA" = "$(git rev-parse origin/main)" ] && return 0
  [ -n "$(git tag --points-at HEAD --list 'release-*')" ] \
    || deploy_source_fail "HEAD is neither origin/main nor a release tag"
}

deploy_source_check() {
  [ -n "${DEPLOY_SOURCE_SHA:-}" ] || return 0   # dry run or before pin: no-op
  [ "$(git rev-parse HEAD)" = "$DEPLOY_SOURCE_SHA" ] || deploy_source_fail "HEAD moved during $1"
  deploy_source_dirty && deploy_source_fail "files changed during $1"
}
```

```bash
# deploy.sh
. scripts/deploy-source-guard.sh
step() { deploy_source_check "$1"; printf '\n▶ %s\n' "$1"; }
[ "$DRY_RUN" = 0 ] && deploy_source_pin
```

```bash
# post-deploy identity check
for _ in $(seq 1 24); do info="$(curl -sf "$APP/api/build-info" || true)"; [ -n "$info" ] && break; sleep 5; done
[ -n "$info" ] || { echo "FAILED: build-info unreachable"; exit 1; }
sha="$(printf '%s' "$info" | sed -n 's/.*"sha" *: *"\([^"]*\)".*/\1/p')"
[ "$sha" = "$EXPECTED_SHA" ] || { echo "FAILED: serving $sha, built $EXPECTED_SHA"; exit 1; }
```

```bash
# long remote deploys
sudo -v
( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) &
trap 'kill $! 2>/dev/null || true' EXIT
```

## Anti-Patterns

- **Checking once at the start.** The failure is a change *during* the build.
- **An override that also skips the clean-tree check.** It becomes the default within a month.
- **`git diff --quiet` as the cleanliness test.** It misses untracked files that the build picks up.
- **Blocking on any non-zero `migrate status`.** It blocks every rollback, so people learn to skip it.
- **`echo WARNING` on a SHA mismatch.** Everyone scrolls past it; the old build keeps serving.
- **Unfrozen installs inside the deploy.** The guard then fires on the deploy's own writes.

## Audit Checklist

- [ ] Every deploy script sources one shared guard; no copy-pasted variants
- [ ] Pin runs before the first mutating stage, skipped only on dry run
- [ ] Stage header function re-verifies HEAD and tree
- [ ] Override env var documented in the runbook and still requires a clean tree
- [ ] All package-manager invocations in the deploy are frozen or locked
- [ ] Drift gate distinguishes behind (block), ahead (warn), unreadable (block)
- [ ] Post-deploy identity check polls with a bound and exits non-zero on mismatch
- [ ] Guard exercised in a scratch repo: clean main, dirty, unpinned, tag, HEAD moved, override
