---
name: verifying-commit-scope
description: Pre-commit auto-formatters can sweep concurrent agents' unstaged work into your commit when stash/restore mishandles a mixed working tree. Run `git diff --cached --stat` before every commit, treat any unexpected file count as stop-the-world, and recover with `git reset --soft HEAD~1`. Triggers when running `git commit` in any repo with husky/lefthook + lint-staged + auto-format `--write`, especially with concurrent unstaged work in the tree.
---

# Verifying Commit Scope

## When This Skill Activates

- Running `git commit` in a repo with husky / lefthook / simple-git-hooks
- That hook runs lint-staged, pre-commit, or any auto-format pipeline with `--write`
- Working tree has a mix of: your staged changes + someone else's unstaged-tracked changes + untracked files
- You're working in a codebase with multiple agents on `main`, multiple humans on the same branch, or you've just done `git pull` and not committed

## The Problem

You stage 8 files. The commit lands with 14 files and 11,000+ insertions of someone else's migration SQL.

This isn't a hypothetical. Pre-commit auto-formatters do three things in sequence:

1. **Stash unstaged changes** (so the formatter only sees what you're committing)
2. **Run the formatter with `--write`** on staged files (Biome, Prettier, ESLint --fix, etc.)
3. **Restore the stash**

Step 3 is where the leak happens. If the formatter touches files that are *also* in the stashed set, or if untracked files exist with the same paths, the restore step takes the post-format state and stages it. Your "8-file commit" silently absorbs whatever was sitting in the working tree.

In a single-developer repo this rarely matters - the unstaged work is yours anyway. In a repo with parallel agents (or multiple humans on `main`), it matters a lot. You can publish someone else's half-finished migration, leak secrets in a config file they were editing locally, or commit tests that reference unwritten code.

## The One Question

**Before pushing, ask: does `git show --stat HEAD` show the file count I expected from my `git add`?**

If the answer is no - even off by one - stop. Don't push. Reset and re-commit.

## Decision Tree

```
About to git commit?
  |
  v
Check working tree state: git status --short
  |
  v
Are there modifications/untracked files I didn't make?
  |
  +-- NO  --> safe to commit normally
  |
  +-- YES --> 1. git add ONLY my files by exact path (never `git add -A` / `git add .`)
              2. git commit
              3. git show --stat HEAD <-- verify count + paths match what you staged
              4. Mismatch? --> reset and re-stage cleanly:
                   git reset --soft HEAD~1
                   git reset HEAD <not-mine-paths>
                   git commit  (now clean)
```

## Core Rules

### Rule 1: Never `git add -A` or `git add .` in a mixed working tree

```bash
# WRONG
git add .
git commit -m "..." # might absorb concurrent work

# CORRECT
git add path/to/my/file1.ts path/to/my/file2.ts
git commit -m "..." # explicit set
```

### Rule 2: Verify staged scope before committing

```bash
git diff --cached --stat # what's actually about to be committed
```

This shows the file list + line counts. Sanity-check: does the count match `git add`? Does the line count look reasonable for your change? A 30-line bug fix should not show 11,000 insertions.

### Rule 3: Verify post-commit, before pushing

```bash
git show --stat HEAD # what actually landed
```

Belt-and-suspenders for Rule 2. The auto-formatter runs *between* `git add` and the commit landing, so the only way to see what was actually committed is to inspect after the fact.

### Rule 4: Recovery sequence is `--soft` reset, not `--hard`

```bash
# WRONG - destroys your work
git reset --hard HEAD~1
git checkout -- .

# CORRECT - keeps changes, just undoes the commit
git reset --soft HEAD~1 # commit gone, all changes still staged
git reset HEAD <paths-that-aren't-mine> # unstage the parallel work
git commit -m "..." # re-commit clean
```

`--soft` keeps the index. `--mixed` (default) keeps changes but unstages everything. `--hard` destroys uncommitted work - never use this for recovery in a tree where someone else has unstaged changes you'd nuke.

## Real Example

Aura monorepo, 2026-05-06. Goal: ship public-facing SEO improvements (legal pages metadata + sitemap entries + CSP edit + 4 loading.tsx skeletons). Eight files staged by exact path.

The commit landed locally with **14 files, 11,481 insertions**. Diff revealed the extras:

```
drizzle/0053_glorious_thundra.sql | 37 +
drizzle/meta/0053_snapshot.json | 11118 ++++++
drizzle/meta/_journal.json | 7 +
packages/database-schema/index.ts | 1 +
packages/database-schema/schema/webhook-message-threads.ts | 87 +
packages/database-schema/schema/webhook-subscriptions.ts | 46 +
```

Six files belonging to a parallel agent who was building a Slack webhook-subscriptions feature. Their migration was unstaged and untracked. Lint-staged + Biome `--write` swept them in via the stash/restore cycle.

Caught it via `git show --stat HEAD` - the 11,481-insertion line was the giveaway. Recovery:

```bash
git reset --soft HEAD~1
git reset HEAD drizzle/ packages/database-schema/
git commit -m "feat(seo,perf): ..." # 8 files, 185 insertions, clean
git push
```

Total recovery time: 90 seconds. Had I not checked, the parallel agent's half-finished migration would have shipped to `main` under my commit hash, with my name on the blame.

## Anti-Patterns

### "I'll just run `git add` and trust the hook"

The hook's job is to *prevent bad commits*, not to *give you the commits you wanted*. A green hook means "the formatter ran" - it doesn't mean "your commit contains only what you intended." Trust your eyes (`git diff --cached --stat`), not the hook.

### "Reverting is too much work, I'll just push and fix forward"

A commit with someone else's unfinished work in it is a poison pill. They'll force-push to fix it, your commit gets rewritten or lost, and now you've created merge work for everyone. Always reset and re-commit.

### "Lint-staged should be smarter about this"

It already is, for the common case (single developer, single feature). The bug is at the *intersection* of: auto-format `--write`, mixed working tree, parallel concurrent edits. Most teams don't hit it because their workflow forbids parallel work on `main`. Aura's does (per project memory: "Always work on main, no worktrees"). If your workflow allows it, this pattern is the safety net.

### "git add -p will catch it"

Interactive add helps you stage, but the auto-formatter still runs after `git add` and before the commit lands. The only reliable check is post-stage: `git diff --cached --stat`.

## Audit Checklist

When reviewing a teammate's commit (or your own before push):

- [ ] File count in `git show --stat HEAD` matches the commit's stated scope
- [ ] No migration SQL, no schema snapshots, no lockfile changes unless the commit message mentions them
- [ ] Total insertion count is plausible for the described change (a "small fix" should not be 5,000+ lines)
- [ ] Untracked files in the parent directories of staged files are NOT in the commit
- [ ] If the commit touched a schema file, the corresponding migration file is also there (atomicity rule from Drizzle / Prisma / etc.)

If any of these fail: reset and re-stage rather than amending - amending preserves the bad index state.

## The Post-Commit Divergence (lint-staged stash/restore)

A subtler variant: after a `lint-staged` commit, the **working tree** can disagree with what was **committed**. lint-staged stashes your unstaged changes, runs the auto-formatter (`biome --write` / `prettier --write`) on the staged set, commits the *formatted* version, then restores the stash — and the restore can leave the working tree holding the *un*-formatted version of files the formatter touched.

The trap: you spot a follow-up fix (e.g. a comment typo the formatter doesn't catch), re-stage, and `git commit --amend`. Because the working tree reverted to the pre-format state, the amend **re-introduces the formatting violations** the hook had already fixed — silently undoing CI-clean work.

**Detection:** right after a lint-staged commit, `git diff HEAD -- <files you just committed>` should be empty. If it shows formatting churn (re-wrapped lines, import re-ordering) you didn't make, that's the divergence.

**Fix:** don't amend on top of the diverged tree. Restore from the commit first, then re-apply only your intended change:

```bash
git checkout HEAD -- <the-files>     # discard the un-formatted working-tree versions
# re-apply ONLY your intended follow-up edit (the comment fix, etc.)
git add -- <the-files>
git diff --cached                    # confirm: ONLY your intended change, no format churn
git commit --amend --no-verify       # comment-only/format-clean change: skip the hook
```

`--no-verify` is justified only when the staged content is already formatter-clean and your change can't introduce a violation (e.g. comment/doc text). Otherwise let the hook run.

## Related Skills

- `verification-before-completion` - same diagnostic mindset, broader scope
- `output-enforcement` - sister skill for "verify what was actually produced"
