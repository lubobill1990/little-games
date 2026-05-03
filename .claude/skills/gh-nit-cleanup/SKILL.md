---
name: gh-nit-cleanup
description: Process a Backlog `nit-cleanup` rolling-issue end-to-end — read every finding (issue body + every comment), classify each as nit / minor / major / spinoff-worthy, fix everything that's safely inline-fixable in one PR, spin the rest into individual issues with PRD + Dev plan, and post a transparent decision log on the rolling issue so the reviewer can see the scope without re-deriving it.
---

# gh-nit-cleanup

Specialist sibling of `implement-task`. **Per `/loop` tick, work at most one nit-cleanup issue.** This skill exists because the rolling cleanup issues bundled by `gh-pr-review` accumulate **dozens** of findings across multiple PRs — too many for `implement-task`'s single-PR cadence to digest, and too varied (literal one-liners next to architectural refactors) for one batch decision.

The skill is opinionated on **scope discipline**: do the trivia in this PR, but never let one cleanup PR balloon into a refactor of the whole codebase. Anything that needs design judgement gets its own issue with a real PRD.

## Identity

Same contract as `implement-task` (see `.claude/skills/implement-task/SKILL.md` § Identity). Pin to `weavejamtom` via process-scoped `GH_TOKEN`:

```bash
export GH_TOKEN=$(gh auth token --user weavejamtom 2>/dev/null)
[ -n "$GH_TOKEN" ] || { echo "weavejamtom not in gh keyring; run: gh auth login --user weavejamtom"; exit 1; }
[ "$(gh api user --jq .login)" = "weavejamtom" ] || { echo "GH_TOKEN didn't resolve to weavejamtom"; exit 1; }
```

Per-worktree git config (in §3 below):

```bash
git -C "$WT" config user.name "Tom Lei"
git -C "$WT" config user.email "tom@weavejam.com"
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'
```

Never `gh auth switch`. Never modify global git config.

## Inputs (hardcoded)

- Repo: `lubobill1990/little-games`
- Project: user `lubobill1990`, project number `5`, project node id `PVT_kwHOAAnKBM4BWZYr`
- Status field id: `PVTSSF_lAHOAAnKBM4BWZYrzhRuER4` — Backlog `c159f539` · InProgress `52594841` · InReview `43a760f0` · ChangesRequested `4c71b2f8` · Done `bb829f92`
- Worktree root: `.implement-task-worktrees/` (shared with `implement-task`; one subdir per task: `task-<n>`).
- State file: `.implement-task-state.json` at repo root (shared with `implement-task` so a tick can see what other implementers are mid-flight). This skill writes to a new top-level key:

```json
{
  "active": { … },                       // owned by implement-task; we read but don't write
  "pending_review": { … },                // owned by implement-task; we read but don't write
  "blocked_global": { … },                // owned by implement-task
  "nit_active": {                         // owned by gh-nit-cleanup
    "<issue_number>": {
      "worktree": ".implement-task-worktrees/task-<n>",
      "branch": "task/<n>-nit-cleanup",
      "started_at": "<iso>",
      "last_step": "classified|fixing|pushed|ci_waiting|ci_red_fixing"
    }
  },
  "nit_pending_review": {                 // mirrors implement-task's pending_review for our PRs
    "issue": <n>, "pr": <pr>, "moved_to_in_review_at": "<iso>"
  }
}
```

Concurrency note: `nit_active.<n>` and `active.<n>` are disjoint by issue number. The shared worktree root is fine because each task gets its own subdir; `git worktree add` would refuse a collision anyway.

## Per-tick priority order

Each `/loop` tick walks this list and stops at the first match.

1. **§1a Resume mid-flight nit work** — `nit_active` has an entry. Healthy worktree → resume from `last_step`. Crashed mid-CI → re-enter §6 (wait for CI).
2. **§1b Wait for our previous nit PR to clear In review** — `nit_pending_review` is set. Block (60s polling, 5 × 10-min wrappers like `implement-task` §1d) until the linked issue's status leaves `In review`. Then exit the tick.
3. **§2 Pick a Backlog nit-cleanup issue.** Filter Project #5 to:
   - `status == "Backlog"` AND
   - labels include `nit-cleanup` AND
   - issue is open AND
   - no `weavejamtom` "🧹 Claimed by gh-nit-cleanup at …" sentinel newer than 4 hours (cross-skill claim race guard).

   Sort by issue number ascending. Take the first.

If nothing claimable: post once-per-day to issue #9 (per `implement-task` §10 dedupe) with reason `no_nit_cleanup_claimable` and exit.

## Procedure

### 1. Sanity (mirrors implement-task §0)

```bash
git worktree prune
ls .implement-task-worktrees/ 2>/dev/null | while read d; do
  git worktree list --porcelain | grep -q ".implement-task-worktrees/$d" \
    || rm -rf ".implement-task-worktrees/$d"
done
```

Then run §Identity check; on failure, jump to `implement-task` §10's auth-wrong path (post to #9, stop).

### 2. Claim and bootstrap

For chosen issue `<N>`:

```bash
TITLE=$(gh issue view <N> --repo lubobill1990/little-games --json title --jq .title)
WT=".implement-task-worktrees/task-<N>"
BRANCH="task/<N>-nit-cleanup"

gh issue comment <N> --repo lubobill1990/little-games \
  --body "🧹 Claimed by gh-nit-cleanup skill at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

git fetch --prune origin
git rev-parse --verify --quiet origin/main >/dev/null \
  || { echo "origin/main missing"; exit 1; }
git worktree add -b "$BRANCH" "$WT" origin/main
touch "$WT/.lock"

git -C "$WT" config user.name "Tom Lei"
git -C "$WT" config user.email "tom@weavejam.com"
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'

scripts/board.sh <N> InProgress
```

Update state: `nit_active.<N> = { worktree, branch, started_at, last_step: "classified" }` (we'll move to `fixing` once classification is done; "classified" is the sentinel that bootstrap completed).

### 3. Read EVERY finding (body + every comment)

Pull both surfaces. The issue body holds the original cleanup-batch findings; every PR review run that produced more nits posted them as comments via `gh-pr-review` §5b or `implement-task` §11e.

```bash
gh issue view <N> --repo lubobill1990/little-games --json body --jq .body > /tmp/nit-<N>-body.md
gh api repos/lubobill1990/little-games/issues/<N>/comments \
  --jq '[.[] | select(.user.login == "weavejamtom" or .user.login == "lubobill1990") | .body]' \
  > /tmp/nit-<N>-comments.json
```

Parse out individual findings. The standard format from both review skills:

```
- [ ] **<file>:<line>** (<severity>) — <title>
  <body>
  [permalink](…)
```

Don't try to be clever about file:line extraction — the structure is rigid. If a comment has the line `### From PR #N @ <sha> — <date>` followed by bullets, treat each bullet as one finding. Skip findings whose checkbox is already `[x]` (someone fixed it earlier).

### 4. Classify

For each finding, assign exactly one bucket:

| Bucket | Definition | Action |
|---|---|---|
| **trivial** | Single-token rename, dead const/var/import removal, comment fix, typo, missing type annotation, missing keycode in a list, single-line constant tweak. < 5 lines, no new logic, no new tests. | Fix inline in this PR. |
| **small-behavior** | Bounded behavior fix in one file: small RNG-order change, missing guard, missing reset, off-by-one, single test added that exercises an existing branch, comment-vs-code mismatch corrected. < 30 lines, < 3 files, no new public API. | Fix inline in this PR. |
| **spinoff** | Anything that needs design judgement OR touches multiple games consistently OR introduces new public API OR is a refactor across > 3 files OR the reviewer's body itself uses words like "either / or", "design choice", "follow-up adjacent". | Spin out as its own issue with PRD + Dev plan (see §5). Do **not** fix inline. |

When unsure, default to **spinoff** — it is cheaper to defer and design properly than to land a half-baked refactor that the next review round will flag again.

### 5. Spin out the spinoffs (one issue each)

For each spinoff finding, create an issue:

```bash
gh issue create --repo lubobill1990/little-games \
  --title "<area>: <short imperative title>" \
  --label "type:task,area:<game-or-infra>" \
  --body "<body — see template below>"
```

**Body template** (PRD + Dev plan, terse — match `CLAUDE.md` §5 brevity):

```markdown
Spun off from #<N> (PR #<source-pr> batch).

## PRD

**Problem.** <2–4 sentences from the finding body, paraphrased — not pasted, since the source has prose-y "I think" framings that don't belong in an acceptance-criteria spec.>

**Goal.** <One sentence describing the desired end-state.>

**Scope.** <Files / modules touched.>

**Non-goals.** <What this issue is NOT doing — usually adjacent things the reviewer also flagged.>

**Acceptance.** <Concrete grep-able / runnable check.>

## Dev plan

**Files.** ~<n> files, ~<n> lines.

**Sequence.** <Bullet list, ideally one commit per logical step.>

**Test strategy.** <New tests? Reuse existing? Manual smoke?>

**Risks.** <Known footguns. If the finding had multiple alternatives, list which one this issue commits to and why.>
```

Add the new issue to Project #5 in Backlog (it'll get refined to Ready + claimed by `implement-task` later):

```bash
NEW_ID=$(gh issue view <new-issue-num> --repo lubobill1990/little-games --json id --jq .id)
gh project item-add 5 --owner lubobill1990 --url <new-issue-url>  # easier than the GraphQL dance
```

(The card lands in Backlog by default. No status flip needed.)

Capture each created issue's number for the decision log in §7.

### 6. Fix the trivial + small-behavior findings inline

Update state: `last_step: "fixing"`.

Implement using `Read` / `Edit` / `Write` against `$WT/`. Group by area (per-game or per-file) for cohesive commits:

```bash
git -C "$WT" add <files>
git -C "$WT" commit -m "<conventional type>: <area> — <one-line subject>

Refs #<N> (<source PR list, e.g. PRs #41, #46>)"
```

Conventional types per `CLAUDE.md` §5. Suggested commit-grouping heuristic: one commit per (area, severity) — e.g. `chore(invaders): drop dead Self consts and unused palette colors`, `fix(2048): cap _settings to one lookup`, `test(snake): cover board-full game_over branch`.

Run GUT after every meaningful chunk to catch regressions early:

```bash
godot --headless --path "$WT/godot" -s addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json
```

Fix red tests in the same chunk before the next chunk. Up to 3 fix iterations per chunk; if still red, comment on the **task issue** with the failing test, leave the worktree intact, and exit (next tick's §1a resumes).

**Hard constraints.**
- Never amend a pushed commit. Never `--force` push. Never `--no-verify`.
- Per-game `core/` must not import `Node` or call OS/Engine APIs (`CLAUDE.md` §5).
- GDScript statically typed.
- **No scope creep.** If during a fix you spot something the reviewer missed, write it down for the *next* nit-cleanup batch — do not fold it in here.

### 7. Decision log on the cleanup issue

Before pushing, post **one comment** on the cleanup issue (`<N>`) summarizing what was done and what wasn't. Reviewer reads this first, so it sets scope expectations.

```bash
gh issue comment <N> --repo lubobill1990/little-games --body "$(cat <<EOF
🧹 **gh-nit-cleanup pass — decision log**

Read <K> findings across the issue body and <M> comments.

### Fixed inline in PR #<PR>

**<area-1> (<count>):**
- <file>:<line> — <one-line summary>
- ...

**<area-2> (<count>):**
- ...

### Spun out as separate issues (with PRD + Dev plan)

Bigger than nit scope or needed design judgement:

- #<spinoff-1> — <one-line title>
- #<spinoff-2> — <one-line title>
- ...

### Out of scope this pass — reasoning

- <finding> — <why deferred — e.g. "needs editor re-save", "blocked on #<other>", "duplicates already-open #<other>">
- ...

The issue stays open until all checkboxes are resolved (either by this PR landing, by the spun-out issues being completed, or by an explicit decision to drop). Next \`/gh-nit-cleanup\` tick will not re-claim while \`In progress\`.
EOF
)"
```

The decision log is the contract with the reviewer: it tells them what to expect in the diff and what to NOT expect. Without it, the reviewer re-derives "what did the implementer choose to fix vs. defer" from scratch every pass, which is exactly the tax this skill is meant to eliminate.

### 8. Push and open PR

```bash
git -C "$WT" push -u origin "$BRANCH"
```

Update `last_step: "pushed"`.

Compute effective diff size (mirrors `implement-task` §8 / `gh-pr-review` §4b rule 5):

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

Build PR body. The cleanup PR is unusual: many small unrelated fixes, but each is justified by the decision log on the issue, so the body is short.

```markdown
Refs #<N>

Cleanup pass on the rolling nit-cleanup issue. Decision log + per-finding scope rationale lives on the issue: <link to the §7 comment>.

## Summary
- <K> trivial / small-behavior findings fixed inline (<count> commits, grouped by area).
- <S> larger findings spun out as #<a>, #<b>, … with PRD + Dev plan.

## How tested
- GUT suite green locally.
- <any specific test added — name it>.

## Estimated effective diff
<EFFECTIVE> lines (total <TOTAL>, excluded <EXCLUDED>).
```

If `EFFECTIVE > 400`: append the same `large-pr-ok` warning as `implement-task` §8. Cleanup PRs **often** exceed 400 effective lines; that's normal. Comment on the cleanup issue (NOT the PR — that channel belongs to `gh-pr-review`):

> ⚠️ This cleanup PR is `<EFFECTIVE>` effective lines (>400). Apply `large-pr-ok` to allow auto-merge, or split the trivial fixes by area into multiple PRs and I'll redo it on the next pass.

Open the PR:

```bash
gh pr create --repo lubobill1990/little-games \
  --base main --head "$BRANCH" \
  --title "chore: nit cleanup batch — <area summary>" \
  --body "$PR_BODY"
```

Capture `<PR>`. Run §9 (wait for CI).

### 9. Wait for CI

Reuse `implement-task` §12 verbatim — the wait-for-CI loop is identity-agnostic. On red, fix locally (consult `docs/lessons/index.md` first) up to 3 attempts; on green, proceed to §10. On timeout / no-checks / 3-attempt red, escalate to issue #9 same as `implement-task` §12 step 4. The §12 lesson-recording machinery (step 5) also applies — if CI took ≥ 2 fix rounds to green, write `docs/lessons/ci-<slug>.md` + index entry.

### 10. Move card and clean up

```bash
scripts/board.sh <N> InReview

rm -f "$WT/.lock"
git worktree remove --force "$WT"
```

Drop `nit_active.<N>`. Set `nit_pending_review = { issue: <N>, pr: <PR>, moved_to_in_review_at: <iso> }` so the next tick's §1b gates on review completion.

The cleanup issue **stays open**. It moves from `In review` (during PR review) to either:
- `Done` if the PR merge auto-closes it via the `Closes #<N>` keyword (we don't use that — see below); OR
- back to `Backlog` if checkboxes remain after this PR lands.

The cleanup issue is intentionally a **rolling** container — `gh-pr-review` and `implement-task` keep appending nits to it. So we **don't** put `Closes #<N>` in the PR body; merging the PR shouldn't close the rolling issue. The PR refs the issue but doesn't close it. The issue's lifecycle is governed by manual close ("all boxes done, drop") or by `gh-pr-review` opening a fresh batch issue when this one moves out of Backlog (the existing convention from `gh-pr-review` SKILL.md §5b).

Since we move the rolling issue to `In review` while the PR is open, `gh-pr-review` will see `status != Backlog` and open a new batch issue on its next nit-emitting run — the rolling pipeline keeps working.

After the PR merges:
- `gh-pr-review`'s post-merge plumbing handles its side.
- `nit_pending_review` clears on the next tick (§1b unblocks once the issue leaves `In review`).
- The cleanup issue's checkboxes for items we fixed are still `[ ]`; check them off as a follow-up commit on the issue body, or leave for the next tick / human to tidy. Recommended: check them off in §7's decision-log comment so the next reader sees status without scrolling.

Print one-line summary:

```
gh-nit-cleanup #<N> "<title>" → PR #<PR> opened (<K> fixed inline, <S> spun out, eff=<n>).
```

## Style guardrails

- All `gh` calls inherit the active account (verified `weavejamtom` at §1).
- Never push `--force`, never `--amend` after push, never `--no-verify`.
- Don't comment on PRs from this skill — `gh-pr-review` owns that channel. Comments go on the cleanup issue or on spun-out issues.
- Don't move cards beyond `InReview` — `gh-pr-review` moves to Done after merge.
- Never modify global git config.
- Per run, one cleanup issue. Strict.
- Always use `git -C "$WT"` and `--path "$WT/godot"`. Never `cd`.
- **Never** write `Closes #<N>` in the cleanup PR body — the issue is rolling, not closeable by a single PR.
- **Always** post the decision log (§7) BEFORE opening the PR, so the PR body can link to it.

## Concurrency notes

- Coexists with `implement-task`: shared worktree root + state file, disjoint top-level state keys (`active` vs `nit_active`), disjoint claim-sentinel emoji (`🔧` vs `🧹`).
- Two `gh-nit-cleanup` instances on the same machine: per-issue worktree dir + `.lock` + claim sentinel handle the race; second instance will find no claimable issue (the first one's claim sentinel is < 4h old) and exit silently.
- Cross-machine: GitHub state (claim comment, board status, branch on origin) is the source of truth.

## When to invoke this skill vs. `implement-task`

| Situation | Skill |
|---|---|
| Backlog issue is a regular `type:task` with PRD + Dev plan, single feature scope | `implement-task` |
| Backlog issue is the rolling `nit-cleanup` with mixed-severity findings across many PRs | `gh-nit-cleanup` |
| Backlog issue is a spinoff *from* `gh-nit-cleanup` (now has its own PRD + Dev plan) | `implement-task` |

If the user invokes `/gh-nit-cleanup` while a different skill's worktree is mid-flight (`implement-task`'s `active` non-empty), `implement-task` §1a's "resume in-progress beats new claim" still applies for the *user's intent* — surface the conflict to the user (via `AskUserQuestion`) before clobbering. The state file's separate top-level keys mean both skills can coexist, but the human typically wants serialized work.
