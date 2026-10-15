---
name: agent-disk-budget
description: >
  Keep coding agents from filling a workstation's disk. Sort every agent output into evidence (keep)
  or scratch (delete when the task ends), enforce it with an age-based purge and a low-disk alert,
  and measure reclaimed space with df, never du. Activates when a disk is nearly full on a machine
  running coding agents, when writing a benchmark, build matrix, database restore or recurring
  automation, when an instruction says "re-run from clean", or when estimating how much a cleanup frees.
---

# Agent Disk Budget

**Principle:** agent work leaves two kinds of output. **Evidence** proves the work and stays.
**Scratch** is anything a command can rebuild, and it needs an owner, an expiry and a meter, or it
stays forever.

**The one question:** *If every agent on this machine stopped today, what would still be on the disk
in a month, and what deletes it?* If the answer is "nothing deletes it", the disk is already filling.

## When This Skill Activates

- A machine that runs coding agents is below 100 GB free
- An agent run will write more than 10 GB: a benchmark, a build matrix, a database restore
- A recurring automation or long loop builds, installs or restores on every iteration
- An instruction tells agents to "re-run from clean" or "start fresh"
- Someone sizes a cleanup with `du`, Finder or a disk-usage app

## Decision Tree

```
Is this output something a command can rebuild?
├── NO → evidence (report, receipt, log, JSON, screenshot, trace, transcript). Keep it.
└── YES → scratch
    ├── Is a process still using it (server, database, gate run)?  YES → leave it, check next run
    ├── Untouched past its age limit?                              NO  → leave it
    ├── Is it a worktree or checkout with uncommitted changes?     YES → report it, never delete
    ├── Is it a container volume?                                  YES → ask; volumes hold data
    └── Delete it, then record the df delta, not the du size
```

Age limits that worked: agent output folders 7 days, agent temp 2 days, agent session logs 30 days,
worktrees 14 days, container images and build cache 7 days.

## Core Rules

1. **"Clean" means a clean build in the same checkout.** Delete build output and reinstall from the
   lockfile. An agent told to "re-run from clean" will otherwise copy the repository, and a loop
   that does this every iteration fills a terabyte in days.
2. **A comparison keeps one baseline and one candidate.** A rebuild replaces the old build. The
   build's receipt (commit, lockfile hash, timing) goes in the evidence; the bytes do not.
3. **Check free space before a big write.** Before a run that writes more than 10 GB, read
   `df -h`. Start with 100 GB free or more, and stop at 50 GB.
4. **A recurring automation deletes each iteration's scratch** before the next iteration starts.
   The automation that creates scratch owns its deletion.
5. **Scratch lives inside the task's own folder.** One root per task lets a purge find it and lets a
   human see what a task cost.
6. **Measure reclaim with `df`, before and after.** On APFS (and on any filesystem with reflinks or
   hard links), `node_modules` installed by bun or pnpm are clones or links of a shared store. `du`
   counts every clone at full size. A folder `du` reported as 139 GB freed 10 GB when deleted.
   Plan with `du`, report with the `df` delta.
7. **Copies of production databases are scratch with a risk attached.** Delete the local copy when
   the investigation ends and keep the queries, receipts and findings.
8. **The purge logs everything and supports a dry run.** Every deletion names the path and the rule
   that removed it.

## Implementation Pattern

Three pieces: a rule in the always-loaded agent instructions, a weekly purge, and a low-disk alert.

**Agent instruction** (add to `AGENTS.md` / `CLAUDE.md`):

```markdown
## Disk budget

Agent work leaves two kinds of output:

- **Evidence** proves the work: reports, receipts, logs, JSON, screenshots, traces. Keep it.
- **Scratch** is anything a command can rebuild: builds, `node_modules`, database copies, source
  snapshots, archives, sandbox runtimes. Delete it when the task ends, and record its hash or
  receipt in the evidence.

- Work in the existing checkout, or one worktree per task.
- A comparison keeps one baseline build and one candidate build.
- Before a run that writes more than 10 GB, run `df -h`. Start with 100 GB free, stop at 50 GB.
- A recurring automation deletes each iteration's scratch before the next iteration starts.
```

**Weekly purge** (Python, scheduled with launchd or cron):

```python
SCRATCH_DIRS = {"node_modules", ".next", ".turbo", "builds", "pgdata", "dev-runtime", ".codex-tmp"}

def newest_mtime(path):
    # Scratch folders count by their own mtime, so a fresh install still marks the parent active
    newest = os.lstat(path).st_mtime
    for root, dirs, files in os.walk(path):
        for name in dirs + files:
            newest = max(newest, os.lstat(os.path.join(root, name)).st_mtime)
        dirs[:] = [d for d in dirs if d not in SCRATCH_DIRS]
    return newest

for task in os.listdir(AGENT_OUTPUT):
    path = os.path.join(AGENT_OUTPUT, task)
    if time.time() - newest_mtime(path) > 7 * DAY:
        strip_scratch(path)            # removes SCRATCH_DIRS and archives over 50 MB, keeps the rest

for wt in stale_worktrees(14 * DAY):
    if git_status_has_changes(wt):
        report(wt)                     # dirty work is the human's call
    else:
        git_worktree_remove(wt)        # branches and commits stay in the main repository

docker_prune(images_older_than="168h", build_cache_older_than="168h")   # volumes untouched
log(f"freed {df_free_after - df_free_before} GB")
```

**Low-disk alert** (every 30 minutes): below 100 GB free, notify at most every 6 hours; below
50 GB, notify every run. Name the biggest folders changed in the last two days, because the cause is
usually one recent agent run.

## Anti-Patterns

- **Archiving scratch.** Moving an old worktree "to be safe" into an archive folder keeps every
  dependency and sandbox byte. Archive the evidence; the commit hash already preserves the code.
- **Preserving every failed build.** "Keep failed observations" applies to the observation records,
  not the build trees behind them.
- **One copy per agent run.** Each worktree with its own install, each benchmark with its own app
  copy, each investigation with its own database restore, all with no expiry.
- **Reporting `du` savings.** A cleanup plan that promised 310 GB delivered 120 GB measured by `df`.
  The difference was clones of package stores that live projects still referenced.
- **Pruning container volumes on a schedule.** Local database volumes hold data a rebuild cannot
  recreate.

## Audit Checklist

- [ ] The always-loaded agent instructions define evidence and scratch
- [ ] "Re-run from clean" wording says "clean build in the same checkout"
- [ ] Every recurring automation deletes its own scratch per iteration
- [ ] A scheduled purge exists, logs each deletion, and has a dry-run flag
- [ ] The purge reports dirty worktrees and never deletes them
- [ ] The purge leaves container volumes alone
- [ ] A low-disk alert fires below a fixed threshold and names recent large folders
- [ ] Cleanup results are reported as `df` deltas
- [ ] No local copy of a production database outlives its investigation
