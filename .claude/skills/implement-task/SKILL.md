---
name: implement-task
description: Claim one Ready task from Project #5, implement its Dev plan in an isolated git worktree as `weavejamtom`, push a branch, open a PR, and move the card to In review. Skips tasks blocked by dependencies and posts a deduped blocker report to issue #9 when stuck. TRIGGER on `/implement-task` or via `/loop 15m /implement-task`.
---

# implement-task

You are acting as the **task implementer** for `lubobill1990/little-games`. Honor the brevity contract in `CLAUDE.md`. Per run, claim **at most one** task — strict, no exceptions even if work finishes early.

This skill is the symmetric counterpart of `gh-pr-review`. The user pushes work entirely from GitHub (Backlog → Ready); you turn Ready tasks into open PRs, then `gh-pr-review` reviews and merges them.

## Per-tick priority order

Each `/loop` tick walks this list and stops at the first match. Whatever it does, the tick exits — wait for the next wakeup.

1. **§1a Resume in-progress work** — an `active` worktree exists from a prior, mid-flight tick (e.g., crashed during code/test/CI-wait).
2. **§1c Handle a Changes-requested PR that hasn't been fixed yet** — reviewer asked for changes; nobody's pushed the fix. Goes into §11.
3. **§1d Wait for the previously-shipped task to clear In review** — if §9 or §11g recorded a `pending_review`, block until that issue leaves the `In review` column before claiming anything new.
4. **§2-§9 Claim a new Ready task.**

If a higher-priority bucket fires, lower buckets are skipped this tick. This keeps the work strictly serialized and predictable for the human.

A tick that pushes commits (§8 or §11g) blocks **in-tick** until CI returns a final verdict — see §12. The implementer is responsible for self-healing red CI; do not hand it off to the next tick.

## Identity

**All GitHub operations and git commits in this skill MUST run as the `weavejamtom` user.** Author/committer of every commit must be `Tom Lei <tom@weavejam.com>`. The `gh-pr-review` skill's auto-merge gate (§4b rule 4) hard-requires this — if the PR's author is anything else, no auto-merge.

Pin this skill's identity to `weavejamtom` via the `GH_TOKEN` env var. **Do not use `gh auth switch`** — it mutates the user-level `~/.config/gh/hosts.yml`, which collides with the `gh-pr-review` skill running on the same machine. `GH_TOKEN` is process-scoped and overrides whatever account is "active", giving us race-free isolation.

```bash
export GH_TOKEN=$(gh auth token --user weavejamtom 2>/dev/null)
[ -n "$GH_TOKEN" ] || { echo "weavejamtom not in gh keyring; run: gh auth login --user weavejamtom"; exit 1; }
[ "$(gh api user --jq .login)" = "weavejamtom" ] || { echo "GH_TOKEN didn't resolve to weavejamtom"; exit 1; }
```

If the keyring lookup fails (account never logged in, or token revoked), STOP and post once-per-day to issue #9 (per §10 dedupe rules) with reason `gh_wrong_user` so the human can re-auth via `gh auth login --user weavejamtom`.

`GH_TOKEN` lives only in the current Bash process — every `/loop` tick re-runs §0, so the export is fresh each time. All `gh` calls in §1–§12 inherit it.

For git over https (the `git push` calls in §4 / §8 / §11g / §12), wire each new worktree's credential helper to the same token so push doesn't fall back to whatever credential the OS keychain has cached:

```bash
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'
# `gh auth git-credential` inherits GH_TOKEN from env → push uses weavejamtom's token.
```

Set the git author/committer identity **per-worktree** in §4 — never mutate global git config.

## Inputs (hardcoded)

- Repo: `lubobill1990/little-games`
- Project: user `lubobill1990`, project number `5`, project node id `PVT_kwHOAAnKBM4BWZYr`
- Status field id: `PVTSSF_lAHOAAnKBM4BWZYrzhRuER4` — Backlog `c159f539` · Ready `391bc048` · In progress `52594841` · In review `43a760f0` · Changes requested `4c71b2f8` · Done `bb829f92`
- Priority field id: `PVTSSF_lAHOAAnKBM4BWZYrzhRuEWM` — P0 `79628723` · P1 `0a877460` · P2 `da944a9c`
- Meta-blocker issue: **#9** (used to flag the human when no task is claimable)
- Worktree root: `.implement-task-worktrees/` (gitignored). One subdir per task: `task-<n>`.
- State file: `.implement-task-state.json` at repo root (gitignored). Kept outside `.claude/` so writes don't trigger settings-dir approval prompts. Schema:

```json
{
  "active": {
    "<issue_number>": {
      "worktree": ".implement-task-worktrees/task-<n>",
      "branch": "task/<n>-<slug>",
      "started_at": "<iso>",
      "last_step": "plan|coding|tests|pushed|pr_opened|cr_fixing|ci_waiting|ci_red_fixing"
    }
  },
  "pending_review": {
    "issue": <issue_number>,
    "pr": <pr_number>,
    "moved_to_in_review_at": "<iso>"
  },
  "blocked_global": {
    "fingerprint": "<sorted joined blocker list>",
    "posted_to_9_at": "<iso>"
  }
}
```

`pending_review` is the single most-recently-shipped task (issue moved to `In review` by §9 or §11g). On the next tick, §1d blocks until that issue leaves `In review` — see §1d for rationale. At most one `pending_review` exists at a time; it's cleared the moment §1d unblocks.

`cr_*` last_step values are used by §11. `ci_waiting` / `ci_red_fixing` mean a §12 wait-for-CI loop was interrupted (process killed, machine rebooted) — §1a resumes those by re-entering §12 with the same PR.

## Procedure

### 0. Cleanup stale worktrees

```bash
git worktree prune
ls .implement-task-worktrees/ 2>/dev/null | while read d; do
  git worktree list --porcelain | grep -q ".implement-task-worktrees/$d" \
    || rm -rf ".implement-task-worktrees/$d"
done
```

Then run the §Identity check. If wrong account, jump to §10 (auth-wrong path) and stop.

### 1. Resume / Changes-requested handling (priority order — first match wins, then exit)

#### 1a. Resume mid-flight in-progress work

Read the state file. If `active` has any entry:

1. Pick the oldest by `started_at`.
2. Verify the worktree dir exists, `.lock` file is present, and `git worktree list` includes it.
3. Verify the linked issue is still on the board in `In progress` (or `Changes requested` for a §11 fix).
4. If healthy → resume from the recorded `last_step`:
   - `plan` / `coding` / `tests` → continue from §6.
   - `pushed` / `pr_opened` → re-enter §12 (wait-for-CI) with the PR found via `gh pr list --head <branch>`.
   - `cr_fixing` → continue from §11c.
   - `ci_waiting` / `ci_red_fixing` → re-enter §12 with the recorded PR number. The wait-for-CI loop is idempotent.
5. If unhealthy (worktree gone, board moved) → drop the `active` entry, fall through to §1c.

Per the user's preference: finishing existing work beats claiming new work.

#### 1c. Pick up an unfixed Changes-requested PR

If §1a didn't fire, scan the board for cards in `Changes requested` whose linked PR is authored by `weavejamtom`:

```bash
gh project item-list 5 --owner lubobill1990 --format json --limit 100 \
  | jq '[.items[] | select(.status == "Changes requested") | {n: .content.number}]'
```

For each, fetch `closedByPullRequestsReferences` and the PR's `author.login`; only consider PRs where author is `weavejamtom`. (PRs from a human or external contributor are out of scope — leave them alone.)

If multiple match, pick the lowest-numbered issue (FIFO by issue id is good enough; this is a low-throughput shop).

If one matches → §11 (the bulk of the Changes-requested workflow lives there). **Exit the tick** when §11 is done, regardless of whether it pushed.

If none match → fall through to §1d.

#### 1d. Wait for the previously-shipped task to clear In review

Strict serialization: don't claim a new Ready task while the last one we shipped is still being reviewed. If the reviewer requests changes, that PR's needs come first (§1c will pick it up next tick); if it merges, we're free to start the next one.

Read `state.pending_review`. If absent → fall through to §2.

If present:

```bash
PENDING=<state.pending_review.issue>

# Block until the issue leaves the In review column. Polls every 30s, no timeout.
WAIT_OUT=$(uv run --quiet --script .claude/skills/implement-task/wait-for-issue-out-of-review.py $PENDING)
RC=$?
if [ $RC -ne 0 ]; then
  echo "wait-for-review script exited $RC; aborting this tick"
  exit $RC
fi
echo "$WAIT_OUT"  # JSON: {"issue": N, "status": "<new status or null>"}
```

The script's behavior matches `gh-pr-review`'s watch script: 60s polling via a single GraphQL call against Project #5, returns the moment the card's status is anything other than `In review`. Same Bash-tool 10-min cap caveat — wrap in the same 5-attempt retry loop as `gh-pr-review` SKILL.md §0:

```bash
PENDING=<state.pending_review.issue>
WAIT_OUT=""
for attempt in 1 2 3 4 5; do
  WAIT_OUT=$(uv run --quiet --script .claude/skills/implement-task/wait-for-issue-out-of-review.py $PENDING)
  RC=$?
  if [ $RC -eq 0 ] && [ -n "$WAIT_OUT" ]; then
    break
  fi
  if [ $RC -ne 0 ] && [ $RC -ne 124 ] && [ $RC -ne 143 ]; then
    echo "wait script exited $RC; aborting this tick"
    exit $RC
  fi
done
if [ -z "$WAIT_OUT" ]; then
  echo "still in review after 5×10min waits; exit cleanly so /loop can recycle"
  exit 0
fi
```

Once the script returns:

1. Clear `state.pending_review`. Persist immediately.
2. **Exit the tick.** The card's new status (`Changes requested` or `Done`) will be picked up by §1c or by `gh-pr-review`'s post-merge plumbing on the *next* tick. Re-running the priority list in the same tick risks racing with state that's only now propagating.

Why exit instead of continuing to §2: the next tick's §1c is exactly the path that handles a freshly-`Changes requested` card; merging into the same tick muddies which step did what. The cost is one extra `/loop` cycle (≤ 1 min), which is negligible compared to review latency.

### 2. Find the next claimable Ready task

```bash
gh project item-list 5 --owner lubobill1990 --format json --limit 100
```

Filter to `status == "Ready"`. Sort by Priority (P0 > P1 > P2 > unset), then by issue number ascending. Walk the list and return the first issue that passes §3.

If none pass: go to §5 (post deduped blocker to #9), then exit with `No claimable tasks at this time.`

### 3. Claim eligibility check

For each Ready candidate, check in order. First failure → record the reason + skip.

#### a. Already-claimed guard

```bash
gh issue view <n> --repo lubobill1990/little-games --json comments \
  --jq '.comments | map(select(.author.login == "weavejamtom" and (.body | startswith("🔧 Claimed by implement-task skill at ")))) | .[-1].createdAt // empty'
```

If a sentinel exists newer than 4 hours → assume another agent owns it; skip with reason `claimed_elsewhere`.

If older than 4h and the issue is still in Ready → assume the prior agent died; proceed (it'll get re-claimed).

#### b. Dependency check

Parse the issue body (and the `task.yml` template's "Depends on" field, which renders as a labeled section). Match `#\d+` references on lines containing `depends on` (case-insensitive) or under a `## Depends on` heading.

For each dep `#N`:

```bash
gh issue view N --repo lubobill1990/little-games \
  --json state,projectItems --jq '{state, status: (.projectItems[0].status.name // null)}'
```

- `state == "CLOSED"` → satisfied.
- `state == "OPEN"` and `status == "Done"` → satisfied (auto-close lag).
- `status == "In review"` → **NOT satisfied**. Reason: `depends_on_in_review:#N`. The whole point of `Depends on` is to wait for that PR to land.
- `status == "Changes requested"` → **NOT satisfied**. Reason: `depends_on_changes_requested:#N`. The dep PR is being iterated on — wait.
- `status` in `In progress|Ready|Backlog|null` → **NOT satisfied**. Reason: `depends_not_started:#N`.

Any unsatisfied dep → skip task with the recorded reason.

#### c. Branch conflict guard

```bash
git ls-remote --heads origin "task/<n>-*" | head -1
```

If anything matches → another worktree owns this issue's branch; skip with reason `branch_exists`.

#### d. PRD / Dev plan presence

Issue body must contain both a `## PRD` (or `# PRD`) section AND a `## Dev plan` (or `## Dev Plan`) section, each with non-empty body content. If either is missing → skip with reason `not_ready_no_plan`. We **do not** write PRDs from this skill — that's the Backlog → Ready refinement step.

### 4. Claim and bootstrap

For the chosen issue `<n>`:

```bash
TITLE=$(gh issue view <n> --repo lubobill1990/little-games --json title --jq .title)
SLUG=$(echo "$TITLE" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40)
WT=".implement-task-worktrees/task-<n>"
BRANCH="task/<n>-$SLUG"

# Post claim sentinel BEFORE any other mutation. Race window is small; combined
# with §3a's 4-hour window this is good enough for a low-concurrency setup.
gh issue comment <n> --repo lubobill1990/little-games \
  --body "🔧 Claimed by implement-task skill at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Sync with remote BEFORE branching. We base the worktree on origin/main, not
# the host repo's local main, so we don't need (and don't want) to fast-forward
# the host's checkout — the user may be on another branch with uncommitted work.
# Pruning deleted refs avoids stale `task/*` branches confusing §3c next run.
git fetch --prune origin

# Sanity-check: origin/main must exist after fetch.
git rev-parse --verify --quiet origin/main >/dev/null || {
  echo "origin/main missing after fetch — aborting"; exit 1;
}

git worktree add -b "$BRANCH" "$WT" origin/main
touch "$WT/.lock"

# Per-worktree git identity. Do NOT use --global.
git -C "$WT" config user.name "Tom Lei"
git -C "$WT" config user.email "tom@weavejam.com"
# Pin git push auth to the same GH_TOKEN this skill exported in §Identity.
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'

scripts/board.sh <n> InProgress
```

Update state file: `active.<n> = { worktree, branch, started_at: <iso>, last_step: "plan" }`. Persist immediately so a crash leaves a recoverable trail.

### 5. If unable to claim ANY task — post to issue #9, deduped

This step runs once §3 has rejected every candidate. Build the **fingerprint** from the rejection reasons:

```
fingerprint = sorted(["#<n>:<reason>" for each rejected candidate]).join(",")
```

Read `state.blocked_global`:

- If `fingerprint` matches AND `posted_to_9_at` is within the last 24 hours → **do not post**. Just exit silently with `Blocked, already reported.`
- Otherwise → post a fresh comment on #9 and update state.

Comment body template:

```markdown
🛑 implement-task skill cannot claim a task.

**Blocked tasks:**
- #<n> — <human reason>
- ...

Will retry on each `/loop` tick. To unblock: <one-line hint per common reason>.
```

Reason → human-text mapping:
- `depends_on_in_review:#N` → "waiting on #N (currently In review — merge it)"
- `depends_on_changes_requested:#N` → "waiting on #N (Changes requested — author needs to push the fix)"
- `depends_not_started:#N` → "waiting on #N (not yet started — that one needs to be implemented first)"
- `not_ready_no_plan` → "Ready but missing PRD or Dev plan section"
- `branch_exists` → "branch `task/<n>-*` already exists on origin (orphaned worktree?)"
- `claimed_elsewhere` → "another agent owns this within the last 4h"

Then update state:

```json
"blocked_global": {
  "fingerprint": "<the fingerprint>",
  "posted_to_9_at": "<iso now>"
}
```

Exit. Do not move any cards.

### 6. Execute the Dev plan

Read the issue body. Treat the `## Dev plan` section as the source of truth, the same way the `Plan` agent's plan file is treated in normal Claude Code use.

Implement step by step using `Read`, `Edit`, `Write` with paths under `$WT/`. After each meaningful chunk:

```bash
git -C "$WT" add <files>
git -C "$WT" commit -m "<conventional type>: <subject>

Refs #<n>"
```

Conventional type per `CLAUDE.md` §5: `feat:` / `fix:` / `test:` / `chore:` / `docs:` / `refactor:` / `ci:`.

Update `state.active.<n>.last_step` after each phase: `coding` → `tests` → `pushed`.

Constraints:
- Never amend a commit that has already been pushed.
- Never `--force` push.
- Never bypass hooks (`--no-verify`).
- Per-game `core/` must not import `Node` or call OS/Engine APIs (`CLAUDE.md` §5).
- GDScript must be statically typed (`CLAUDE.md` §5).

### 7. Verify locally

Run GUT tests in the worktree (CI runs the same command):

```bash
godot --headless --path "$WT/godot" -s addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json
```

If tests pass → continue to §8.

If tests fail → fix in the same worktree. Up to **3 fix iterations**. If still red after 3 attempts:
- Comment on the **task issue** (not #9) with the failing test names + a brief "blocked, please advise".
- Leave the card in `In progress` and the worktree intact.
- Exit. The next `/loop` run's §1 will resume.

### 8. Push and open PR

```bash
git -C "$WT" push -u origin "$BRANCH"
```

Update `last_step: pushed`.

Compute effective diff size (mirrors `gh-pr-review` §4b rule 5):

```bash
TOTAL=$(git -C "$WT" diff --shortstat origin/main \
  | grep -oE '[0-9]+ insertion|[0-9]+ deletion' \
  | grep -oE '[0-9]+' | paste -sd+ - | bc)
TOTAL=${TOTAL:-0}

EXCLUDED=$(git -C "$WT" diff --numstat origin/main \
  | awk '$3 ~ /^(godot\/)?tests\/|^(godot\/)?assets\/|^docs\/|\.import$|\.translation$|\.lock$|^[^/]+\.md$|^package-lock\.json$|^pnpm-lock\.yaml$/ \
         {sum += $1 + $2} END {print sum+0}')

EFFECTIVE=$((TOTAL - EXCLUDED))
```

Build the PR body. Include the `Estimated effective diff` line so `gh-pr-review` (and the human) can sanity-check:

```markdown
Closes #<n>

## How tested
- GUT tests pass locally in worktree
- <other items pulled from the Dev plan's test strategy>

## Estimated effective diff
<EFFECTIVE> lines (total <TOTAL>, excluded <EXCLUDED>).
```

If `EFFECTIVE > 400`, append:

```markdown
⚠️ Exceeds 400 effective lines. Issue must carry the `large-pr-ok` label for auto-merge; otherwise human review will be required.
```

Open the PR:

```bash
gh pr create --repo lubobill1990/little-games \
  --base main --head "$BRANCH" \
  --title "<conventional title from first commit>" \
  --body "$PR_BODY"
```

If `EFFECTIVE > 400` AND the issue lacks `large-pr-ok`, comment on the issue (not the PR — `gh-pr-review` owns PR comments):

> ⚠️ This task produced a PR of `<EFFECTIVE>` effective lines (>400). Apply `large-pr-ok` to allow auto-merge, or split the task and I'll redo it on the next pass.

Open the PR regardless — the human can decide.

After `gh pr create` returns, capture `<PR>` and run **§12 (wait for CI)**. Only proceed to §9 once §12 reports green. If §12 escalates (timeout or 3 fix-iterations red), follow its exit rules — do NOT move the card to InReview.

### 9. Move card and clean up

```bash
scripts/board.sh <n> InReview

rm -f "$WT/.lock"
git worktree remove --force "$WT"
```

Drop `state.active.<n>`. Clear `state.blocked_global` (we made progress, so the next blocked-state will be fresh). **Set `state.pending_review = { issue: <n>, pr: <pr>, moved_to_in_review_at: <iso> }`** so the next tick's §1d blocks until this card leaves `In review` (review approved & merged → Done, or reviewer requested changes → Changes requested).

Print one-line summary:

```
Implemented #<n> "<title>" → PR #<pr> opened (eff=<n>, total=<n>).
```

### 10. Failure paths

- **`gh auth token --user weavejamtom` returns empty** at §0 (account missing from keyring or token revoked): post-once-per-day to #9 with reason `gh_wrong_user`. Fingerprint dedupe applies. Stop.
- **Worktree add fails** (e.g., branch exists despite §3c, or filesystem error): drop the candidate (don't `scripts/board.sh InProgress`), don't post the claim sentinel — actually, if the sentinel was already posted, post a corrective comment on the same issue: `❌ Claim aborted: <reason>. Skipping this run.` and try the next candidate.
- **Tests fail after 3 iterations** (§7): comment on the task issue, leave In progress, exit.
- **Push rejected** (branch protection, etc.): comment on the task issue with the error, leave In progress, exit.
- **`gh pr create` fails**: same as push rejection. Don't move the card to InReview.
- **Catastrophic uncaught error**: state file remains; next run's §1 picks it up. Don't try to "clean up" by deleting the worktree on uncertain failure paths — better a stuck task than lost work.

### 11. Handle a Changes-requested PR (called from §1c)

This section runs when there's a PR by `weavejamtom` whose linked issue is in `Changes requested` and we haven't yet pushed a fix. The job: read the reviewer's findings, fix what matters in code, route the rest into the rolling **Nit & minor cleanup** issue, push, and park for CI.

**Restraint contract.** The user explicitly wants this skill to stay conservative:

- **Always fix:** every `blocker` / `major` finding, plus any `minor` / `nit` that's a "举手之劳" — purely literal/stylistic edits (rename, typo, comment polish, removed unused var, missing type annotation, missing keycode in a list, single-line constant tweak).
- **Defer to cleanup issue:** any `minor` / `nit` that requires multi-line refactor, new/changed tests, new abstraction, API rename across files, or design judgement.
- **Never expand scope:** even if you spot something the reviewer missed, don't fix it on this pass. The PR is for the reviewer-flagged set only.

#### 11a. Fetch the review and check out the PR branch

```bash
PR=<pr_number>
N=<linked_issue>
HEAD_BRANCH=$(gh pr view $PR --repo lubobill1990/little-games --json headRefName --jq .headRefName)
HEAD_SHA=$(gh pr view $PR --repo lubobill1990/little-games --json headRefOid --jq .headRefOid)

WT=".implement-task-worktrees/task-$N"
git fetch origin "$HEAD_BRANCH"
git worktree add "$WT" "origin/$HEAD_BRANCH"
touch "$WT/.lock"
git -C "$WT" checkout -B "$HEAD_BRANCH" "origin/$HEAD_BRANCH"
git -C "$WT" config user.name "Tom Lei"
git -C "$WT" config user.email "tom@weavejam.com"
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'
```

Update state: `active.<N> = { worktree: $WT, branch: $HEAD_BRANCH, started_at: <iso>, last_step: "cr_fixing" }`.

#### 11b. Read the latest CHANGES_REQUESTED review

The review body holds the summary; the inline comments are the actionable items.

```bash
# Latest CHANGES_REQUESTED review by lubobill1990
REVIEW_ID=$(gh api repos/lubobill1990/little-games/pulls/$PR/reviews \
  --jq '[.[] | select(.state == "CHANGES_REQUESTED" and .user.login == "lubobill1990")] | last | .id')

# Body
gh api repos/lubobill1990/little-games/pulls/$PR/reviews/$REVIEW_ID --jq .body

# Inline comments (each has path, line, body, in_reply_to_id, etc.)
gh api repos/lubobill1990/little-games/pulls/$PR/reviews/$REVIEW_ID/comments
```

For each inline comment, classify by reading the comment body:
- `**Blocker**` / `Blocker —` → blocker
- `**Major**` / `Major —` / `Missing` (when in review-skill format) → major
- `**Minor**` / `Minor —` / `**Nit**` / `Nit —` → minor or nit
- Otherwise infer from severity language ("must" / "required" / "violates" → major+; "consider" / "could" → minor)

If the review body has a `### Nits` section without an inline location, treat each bullet as a nit finding.

#### 11c. Fix blockers and majors

Implement each blocker / major fix in `$WT` using `Read` / `Edit` / `Write`. Commit per logical fix:

```bash
git -C "$WT" add <files>
git -C "$WT" commit -m "fix: <subject>

Refs #$N"
```

Run GUT (same as §7) until green. Up to 3 fix iterations. If still red after 3 → comment on the **task issue** with the failing tests + "stuck after fix attempts; please advise". Leave card in `Changes requested`. **Exit the tick.**

#### 11d. Triage minor / nit findings

For each `minor` or `nit`:

1. **举手之劳 test (one of these must hold):**
   - The change is a single-token rename, comment fix, typo, missing keycode in a list, missing type annotation, removed dead var.
   - The change touches one location, < 5 lines total, no new logic, no new tests.

   If yes → fix it inline, commit it together with the blocker/major fixes (one commit per finding is fine, or batch as `chore: address review nits` if cohesive).

2. **Otherwise → cleanup issue.** Collect into a list to be appended to the rolling `Nit & minor cleanup` issue in §11e.

If you're unsure whether something qualifies, default to the cleanup issue — it's cheaper to defer than to expand scope mid-fix.

#### 11e. Append deferred nits to the rolling cleanup issue (with dedup)

This mirrors `gh-pr-review` SKILL.md §5b but is invoked from a different surface.

1. Find the open rolling issue (label `nit-cleanup`, status Backlog):

   ```bash
   gh issue list --repo lubobill1990/little-games \
     --label nit-cleanup --state open --json number,title,projectItems \
     --jq '.[] | select(.projectItems[]? | .status.name == "Backlog") | .number' \
     | head -1
   ```

2. **Dedup against existing content.** Fetch the issue body and all comments; build a set of existing finding identifiers. The identifier is `(file_path, line_number, normalized_title)` where `normalized_title` is lowercased, whitespace-collapsed, leading severity tag stripped.

   ```bash
   ROLLING=<n>
   gh issue view $ROLLING --repo lubobill1990/little-games --json body --jq .body > /tmp/cleanup_body.md
   gh api repos/lubobill1990/little-games/issues/$ROLLING/comments --jq '.[].body' >> /tmp/cleanup_body.md
   ```

   For each candidate finding to append, grep `/tmp/cleanup_body.md` for `<file>:<line>` AND a sufficient title-substring match (e.g. first 6 normalized words). If found → drop the candidate (already there, even if from this same PR's earlier review pass).

3. If after dedup the candidate list is empty → skip §11e entirely; go to §11f.

4. Build the batch block (same shape as gh-pr-review §5b step 2):

   ```markdown
   ### From PR #<pr> @ <short_sha> — <YYYY-MM-DD> (deferred by implement-task)

   - [ ] **<file>:<line>** (<severity>) — <title>
     <body>
     [permalink](https://github.com/lubobill1990/little-games/blob/<HEAD_SHA>/<file>#L<line>)
   ```

5. **If a rolling issue exists:** append as a comment.
   **If none exists:** create one with title `Nit & minor cleanup — batch starting <YYYY-MM-DD>`, label `nit-cleanup,backlog`, body matching the gh-pr-review §5b template, then add to Project #5 with Status=Backlog Priority=P2 (mutations from gh-pr-review §5).

6. Capture `<cleanup_issue_url>` and `<batch_url>` (same rules as gh-pr-review §5b step 4).

#### 11f. Backlink from the PR and the task issue

If §11e actually appended anything, post the same note to both surfaces:

```bash
NOTE="🧹 Deferred <K> nit/minor finding(s) from this round to the rolling cleanup issue: <cleanup_issue_url> (batch: <batch_url>). Will be picked up there separately."

gh issue comment $PR --repo lubobill1990/little-games --body "$NOTE"
gh issue comment $N  --repo lubobill1990/little-games --body "$NOTE"
```

Skip both calls if §11e was a no-op.

#### 11g. Push and wait for CI

```bash
git -C "$WT" push origin "$HEAD_BRANCH"
```

Update state: `active.<N>.last_step = "ci_waiting"`, record `cr_pushed_sha = <HEAD_SHA after push>`.

Run **§12 (wait for CI)** with this `<PR>`. §12 owns the verdict — green / red-then-fixed / red-after-3-attempts / timeout — and updates state and the card per its own exit rules. On green, §12 moves the card to **InReview** so `gh-pr-review` (which only scans InReview cards) picks it up for the next round.

When §12 returns, print the round summary:

```
#<N>: pushed fix on PR #<PR> (<X> blockers/majors fixed inline, <Y> nits inline, <Z> deferred to cleanup #<M>); CI <verdict>.
```

`<verdict>` is one of `green`, `red-then-fixed-green`, `red-after-3-attempts`, `timeout`.

### 12. Wait for CI (subroutine called from §8 and §11g)

Block in-tick on the PR's checks until they reach a final verdict, then act. The implementer is responsible for self-healing red CI; do **not** hand off to the next tick.

**Inputs:** `<PR>` (the PR number), `<WT>` (the worktree path), `<N>` (linked issue), `<BRANCH>` (the head branch), call-site (§8 = new PR / §11g = CR fix). Caller has already set `last_step = "ci_waiting"` and persisted state.

**Step 1 — compute the timeout.**

```bash
# Workflow file that runs the GUT suite — the gate we care about.
WORKFLOW_FILE=".github/workflows/ci.yml"   # adjust if this repo uses a different filename

# Last 5 successful runs on `main` (proxy for "healthy CI duration").
MAX_SUCCESS=$(gh run list --repo lubobill1990/little-games \
  --workflow "$WORKFLOW_FILE" --branch main --status success --limit 5 \
  --json startedAt,updatedAt \
  --jq '[.[] | (((.updatedAt|fromdateiso8601) - (.startedAt|fromdateiso8601)))] | max // 0')

# Floor 600s (10 min). Cap 3600s (1h) — sanity bound; CI shouldn't legitimately exceed this.
TIMEOUT_S=$(( MAX_SUCCESS * 2 ))
[ "$TIMEOUT_S" -lt 600 ] && TIMEOUT_S=600
[ "$TIMEOUT_S" -gt 3600 ] && TIMEOUT_S=3600
```

If the workflow file name differs, discover via `gh workflow list` and update the constant. If `gh run list` returns no successful samples (fresh repo / first PR), `MAX_SUCCESS=0` and the floor (600s) applies.

**Step 2 — poll until terminal.** Every 20 seconds, query the rollup. Don't poll tighter than 20s — GitHub rate-limits and CI is minute-scale.

```bash
DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
VERDICT=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  STATE=$(gh pr view "$PR" --repo lubobill1990/little-games \
    --json statusCheckRollup \
    --jq '[.statusCheckRollup[] | (.conclusion // .status // "PENDING")] as $s
          | if ($s | length) == 0 then "NO_CHECKS"
            elif any($s[]; . == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED") then "RED"
            elif all($s[]; . == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") then "GREEN"
            else "PENDING" end')
  case "$STATE" in
    GREEN|RED|NO_CHECKS) VERDICT="$STATE"; break ;;
  esac
  sleep 20
done
[ -z "$VERDICT" ] && VERDICT="TIMEOUT"
```

`NO_CHECKS` is terminal — a PR with zero registered checks is a CI config problem, not a transient delay.

**Step 3 — branch on the verdict.**

- **GREEN.**
  - **If `ci_fix_attempts >= 2`** (CI was red and required ≥2 attempts to go green) → run **step 5 (record CI lesson)** before continuing.
  - Caller §8 (new PR): clear `last_step` and return `green`. §8 continues to §9 (move card to InReview, clean up).
  - Caller §11g (CR fix): run `scripts/board.sh <N> InReview` (so `gh-pr-review` — which only scans InReview cards — picks the PR up for re-review), then clean up `rm -f $WT/.lock; git worktree remove --force $WT`, drop `active.<N>`, **set `state.pending_review = { issue: <N>, pr: <PR>, moved_to_in_review_at: <iso> }`** (same rationale as §9 — the next tick's §1d will gate on this). Return `green` (or `red-then-fixed-green` if step 4 ran).

- **RED.**
  - Pull failing-job logs:

    ```bash
    RUN_ID=$(gh pr view "$PR" --repo lubobill1990/little-games \
      --json statusCheckRollup \
      --jq '[.statusCheckRollup[] | select((.conclusion // "") == "FAILURE") | .detailsUrl] | .[0]' \
      | grep -oE '/runs/[0-9]+' | grep -oE '[0-9]+')
    gh run view "$RUN_ID" --repo lubobill1990/little-games --log-failed > "$WT/.ci-fail.log"
    ```

  - Set `last_step = "ci_red_fixing"`. Increment `ci_fix_attempts` in state (initialize to 0 on first red). Persist.
  - If `ci_fix_attempts > 3` → escalate (step 4) with reason `red-after-3-attempts`.
  - **Before fixing, consult `docs/lessons/index.md`** if it exists. Grep titles and one-line summaries for keywords from `.ci-fail.log` (the failing test name, error message phrase, file path involved). If a lesson matches, read the full lesson file first — past-me already paid for that knowledge. Don't blindly copy the fix; verify the symptom matches before applying.
  - Otherwise: read `.ci-fail.log`, fix in `$WT` using `Read` / `Edit` / `Write`. Run GUT locally (§7) until green. Commit (`fix(ci): <subject>` — `Refs #<N>`). Push:

    ```bash
    git -C "$WT" push origin "$BRANCH"
    ```

  - Reset `last_step = "ci_waiting"`, persist, **loop back to step 1** (recompute deadline so each round gets a fresh timeout — CI duration depends on the run, not on prior wall time).

- **NO_CHECKS** → escalate (step 4) with reason `no-checks`.
- **TIMEOUT** → escalate (step 4) with reason `timeout`.

**Step 4 — escalate.**

```bash
SUMMARY="Latest checks: $(gh pr checks "$PR" --repo lubobill1990/little-games || true)"

gh issue comment "$N" --repo lubobill1990/little-games --body "🛑 implement-task: blocked on CI for PR #$PR — <reason>.

$SUMMARY

Worktree left intact at \`$WT\`; state preserved so the next \`/implement-task\` tick will resume the §12 loop. To unblock manually: push a fix to \`$BRANCH\` (next tick will re-poll and proceed) or close the PR (next tick will drop the worktree)."
```

Leave the worktree intact and `active.<N>` populated. Do NOT move the card. Return the reason to the caller. Caller exits the tick.

**Idempotence.** §12 is safe to re-enter (§1a does this when a tick was killed mid-wait): step 1 recomputes the deadline; step 2 polls fresh; `ci_fix_attempts` persists across re-entries so the 3-attempt budget can't be reset by crashing.

**Step 5 — record a CI lesson (only when `ci_fix_attempts >= 2`).**

Goal: when CI took ≥ 2 fix rounds to go green, distill what was actually wrong into a teaching note future ticks can learn from. One-shot greens skip this step entirely — the noise isn't worth it.

Lessons live in `docs/lessons/` as a hand-curatable knowledge base:

- `docs/lessons/index.md` — one-line entries, oldest first, format `- [<short title>](<filename>) — <one-sentence what & how>`.
- `docs/lessons/ci-<slug>.md` — one lesson per file. CI-related lessons MUST start with `ci-`; future lesson categories will get their own prefix (e.g. `gut-`, `gd-`).

Procedure:

1. **Gather evidence from this run.** `$WT/.ci-fail.log` is the *latest* failure log (each red round overwrites it); for the full picture, also pull commit messages added during the fix loop:

   ```bash
   FIX_COMMITS=$(git -C "$WT" log --format='%h %s' "origin/main..HEAD" -- | grep -iE '^[0-9a-f]+ fix(\(ci\))?:')
   FIX_DIFF=$(git -C "$WT" log -p --format='### %h %s%n' "origin/main..HEAD" -- | head -300)
   FAIL_LOG_TAIL=$(tail -200 "$WT/.ci-fail.log" 2>/dev/null)
   ```

2. **Decide if this round actually taught us something.** Skip recording (and just return `green`) if any of these hold:
   - The failure was a transient infra blip (network timeout, runner pre-empted) and the fix was just a re-run with no code change.
   - The fix is identical to a lesson already in `docs/lessons/index.md` — read the index first, grep titles for the failure signature.
   - The lesson would be content-free (e.g. "fixed a typo"). The bar is "future me would want to know this before stepping on the same rake."

3. **Author the lesson file.** Pick a short kebab-case slug describing the *root cause*, not the symptom. Examples of good slugs: `ci-headless-godot-needs-display-arg`, `ci-gut-flag-name-changed`, `ci-windows-path-separator-in-glob`. Avoid issue-numbered or PR-numbered slugs — the lesson should be reusable.

   Write `docs/lessons/ci-<slug>.md` with this shape:

   ```markdown
   # <Title — same as slug, human-cased>

   **First seen:** PR #<PR>, issue #<N>, <YYYY-MM-DD>
   **Attempts to green:** <ci_fix_attempts>

   ## Symptom

   <2–4 sentence description of how the failure presented in CI — paste the key error line(s) verbatim from .ci-fail.log so future grep finds it>

   ## Root cause

   <what was actually wrong, in 1–3 sentences. NOT "I forgot to X" — write it so it's useful to a stranger>

   ## Fix

   <the actual change, with a code block if it's small enough. If multi-file, summarize and link to the merged commit SHAs>

   ## How to avoid next time

   <one or two bullets — concrete heuristic, e.g. "before adding a new GUT flag, check addons/gut/gut_cmdln.gd --help in the vendored version, not online docs">
   ```

   Use the gathered `FAIL_LOG_TAIL`, `FIX_COMMITS`, and `FIX_DIFF` as raw material. Write the markdown with `Write`, not `gh` — these are local files committed to the repo.

4. **Update the index.** `docs/lessons/index.md` is the entry point; create it on first lesson. One-line entries, alphabetical by filename within each section. If the file doesn't exist, create with this header:

   ```markdown
   # Lessons

   Hand-curated notes from past mistakes that took multiple rounds to diagnose. Organized by category; each entry links to a standalone `<category>-<slug>.md` file.

   ## CI

   - [<short title>](ci-<slug>.md) — <one-sentence summary>
   ```

   On subsequent lessons, insert under the appropriate category in alphabetical order. Keep each line under ~150 chars.

5. **Commit the lesson alongside the CI fix.** This way the lesson lands on `main` together with the fix, and `git log docs/lessons/` becomes a chronological learning trail.

   ```bash
   git -C "$WT" add docs/lessons/index.md "docs/lessons/ci-<slug>.md"
   git -C "$WT" commit -m "docs(lessons): record ci-<slug> from PR #$PR

   Refs #$N"
   git -C "$WT" push origin "$BRANCH"
   ```

   This push will trigger another CI round. **Do not** loop on it from inside step 5 — return to step 2's polling loop with `last_step = "ci_waiting"` and let the existing wait-for-CI machinery handle it. (The lesson commit is doc-only, so it should green on the first try; if it doesn't, that's a real CI issue worth another round.)

6. After the lesson-commit CI round goes green, control returns here, but `ci_fix_attempts` is unchanged from before — and the lesson file already exists, so step 5's "skip if duplicate" guard in (2) prevents re-recording. Proceed to the GREEN branch's caller-specific cleanup as normal.

**Why only `>= 2`:** a single red→green round usually means a typo or trivial oversight already captured by the commit message. Two or more rounds means I misdiagnosed at least once — that's where the learning is.

## Style guardrails

- All `gh` calls inherit the active account (verified `weavejamtom` at §0).
- Never push `--force`, never `--amend` after push, never `--no-verify`.
- Don't comment on PRs from this skill — `gh-pr-review` owns that channel.
- Don't move cards beyond `InReview` — `gh-pr-review` moves to Done after merge.
- Never modify global git config.
- Per run, claim at most 1 task. If you finished a task in §1's resume path, do not also try to claim a new one — exit cleanly.
- Always use `git -C "$WT"` and `--path "$WT/godot"`. Never `cd`. The session may be shared.

## Concurrency notes

This skill is designed to run alongside other instances of itself (different Claude sessions, future agent platforms). The guards:

- Per-task worktree dir + `.lock` file.
- Per-task branch name (`task/<n>-<slug>`) — push race resolved by `git push -u`.
- Claim sentinel comment on the issue with 4-hour staleness window.
- State file is local to one Claude session — DO NOT rely on it for cross-session coordination. The GitHub state (claim comment, board status, branch on origin) is the source of truth.

If two instances race on §4, the second will fail at `git worktree add` (branch already taken) and back out via §10 — acceptable.
