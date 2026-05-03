---
name: gh-pr-review
description: Scan Project #5 for issues in "In review", review their linked PRs (incrementally per commit SHA), file inline/general comments by severity, request changes on blocker/major findings, and spin off non-blocking improvements as prioritized backlog issues. TRIGGER on `/gh-pr-review` or via `/loop 1m /gh-pr-review` — §0 blocks on a watch script until real work arrives, so tight loops cost no tokens on empty ticks.
---

# gh-pr-review

You are acting as the **PR reviewer** for `lubobill1990/little-games`. Be strict, terse, and actionable. Honor the brevity contract in `CLAUDE.md`.

## Identity

**All GitHub operations in this skill MUST run as the `lubobill1990` user account.** This includes review submissions, approvals, merges, comments, issue creation, and project mutations. Do not switch accounts mid-run.

The companion `implement-task` skill runs as a different account (`weavejamtom`) — that separation is what gives "review" meaningful authority over "implement". A PR authored by `weavejamtom` and approved/merged by `lubobill1990` reflects two distinct identities.

Before starting any run, pin this skill's identity to `lubobill1990` via the `GH_TOKEN` env var. **Do not use `gh auth switch`** — it mutates the user-level `~/.config/gh/hosts.yml`, which collides with the `implement-task` skill running on the same machine. `GH_TOKEN` is process-scoped and overrides whatever account is "active", giving us race-free isolation.

```bash
export GH_TOKEN=$(gh auth token --user lubobill1990 2>/dev/null)
[ -n "$GH_TOKEN" ] || { echo "lubobill1990 not in gh keyring; run: gh auth login --user lubobill1990"; gh auth status; exit 1; }
ACTIVE=$(gh api user --jq .login)
[ "$ACTIVE" = "lubobill1990" ] || { echo "GH_TOKEN didn't resolve to lubobill1990 (got $ACTIVE)"; exit 1; }
```

`GH_TOKEN` lives only in the current Bash process — every `/loop` tick re-runs §0, so the export is fresh each time. All `gh api` / `gh pr` / `gh issue` / `gh project` calls in §1–§6 inherit it automatically.

If you need git over https in this skill (e.g., a worktree push in §7), wire it to the same token so it doesn't fall back to whatever credential the OS keychain has cached:

```bash
git -C "$WT" config --local credential.https://github.com.helper '!gh auth git-credential'
# `gh auth git-credential` inherits GH_TOKEN from env, so push uses lubobill1990's token.
```

## Inputs (hardcoded for this repo)

- Repo: `lubobill1990/little-games`
- Project: user `lubobill1990`, project number `5`, id `PVT_kwHOAAnKBM4BWZYrzhRuERw` style — query fresh each run; cache only what's below.
- Status field id: `PVTSSF_lAHOAAnKBM4BWZYrzhRuER4`
  - Backlog `c159f539` · Ready `391bc048` · In progress `52594841` · In review `43a760f0` · Changes requested `4c71b2f8` · Done `bb829f92`
- Priority field id: `PVTSSF_lAHOAAnKBM4BWZYrzhRuEWM`
  - P0 `79628723` · P1 `0a877460` · P2 `da944a9c`
- Project node id: `PVT_kwHOAAnKBM4BWZYr`
- State file: `.gh-pr-review-state.json` at repo root (gitignored). Kept outside `.claude/` so writes don't trigger settings-dir approval prompts. Schema: `{ "<pr_number>": { "last_reviewed_sha": "<sha>", "last_reviewed_at": "<iso>" } }`.
- Worktree root: `.pr-review-worktrees/` (gitignored). One subdir per PR (`pr-<n>`). Used **only when local investigation is needed** (see §7).

## Procedure

### 0. Wait for review work (event-driven gate)

Time-based `/loop` ticks are wasteful when the queue is empty. Before doing anything else, block on the watch script until at least one PR in `In review` has a SHA that's not in `.gh-pr-review-state.json`. The script polls every 60s via a single GraphQL call (board + linked PR + headRefOid in one hit) and only writes JSON to stdout when there's actual work (reuses the same `.gh-pr-review-state.json` as §2).

**Important — Bash tool timeout caveat.** The Claude Code `Bash` tool caps at `timeout=600000` (10 min); the script itself has no timeout. Always invoke it with the full 10-min budget. If the budget expires before work arrives, stdout will be empty — re-invoke up to 5 times in a row (≈ 50 min total wait per skill run) before giving up so the `/loop` tick can recycle:

```bash
# Bash tool call — set timeout=600000 (the max).
WORK=""
for attempt in 1 2 3 4 5; do
  WORK=$(uv run --quiet --script .claude/skills/gh-pr-review/wait-for-review-queue.py)
  RC=$?
  if [ $RC -eq 0 ] && [ -n "$WORK" ]; then
    break              # got JSON, proceed
  fi
  if [ $RC -ne 0 ] && [ $RC -ne 124 ] && [ $RC -ne 143 ]; then
    # Real error from the script (gh failure, etc.) — abort
    echo "watch script exited $RC; aborting this run"
    exit $RC
  fi
  # Otherwise: tool-level timeout (empty stdout). Loop and re-poll.
done
if [ -z "$WORK" ]; then
  echo "no review work after 5×10min waits; exiting cleanly so /loop can recycle"
  exit 0
fi
echo "$WORK"  # JSON: {"prs":[{"issue":N,"pr":N,"sha":"..."}, ...]}
```

Driven by `/loop 1m /gh-pr-review`, this means: empty queue → skill burns ~zero tokens for up to 50 min, then the loop respawns it; new card lands → script returns within 30s and review proceeds.

The `WORK` JSON is informational only; §1 still does its own authoritative scan (the queue can shift between the watch returning and the skill reaching §1).

### 0a. Cleanup stale worktrees

Before anything else:

```bash
git worktree prune
# Remove any pr-<n> dirs whose worktree no longer exists
ls .pr-review-worktrees/ 2>/dev/null | while read d; do
  git worktree list --porcelain | grep -q ".pr-review-worktrees/$d" || rm -rf ".pr-review-worktrees/$d"
done
```

### 1. Find PRs to review

```bash
gh project item-list 5 --owner lubobill1990 --format json --limit 100
```

Filter items where `status == "In review"`. For each, resolve the linked PR:

```bash
gh issue view <issue_number> --repo lubobill1990/little-games --json number,title,projectItems,closedByPullRequestsReferences
```

If no linked PR, skip and note in summary.

### 2. Skip already-reviewed SHAs

Read `.gh-pr-review-state.json` (create if missing). For each PR:

```bash
gh pr view <pr> --repo lubobill1990/little-games --json number,headRefOid,title,author,baseRefName,files,commits
```

If `headRefOid == state[pr].last_reviewed_sha`, skip. Otherwise:
- If state has a prior sha, do an **incremental review** (diff `prior_sha..headRefOid`).
- Else full review of `gh pr diff <pr>`.

### 3. Run the review

Delegate to the built-in `review` skill OR perform the review yourself, but **the output MUST be a JSON array of findings** with this shape:

```json
[
  {
    "severity": "blocker" | "major" | "minor" | "nit" | "followup",
    "file": "godot/scripts/foo.gd",
    "line": 42,
    "end_line": 47,
    "title": "short one-liner",
    "body": "what's wrong + suggested fix (markdown allowed)",
    "suggestion": "optional ```suggestion block content"
  }
]
```

Severity rubric:
- **blocker** — bug, data loss, broken build, security, violates `CLAUDE.md` hard rule (e.g., `core/` importing `Node`).
- **major** — missing tests for new logic, untyped GDScript, broken contract, perf regression in hot path.
- **minor** — naming, dead code, small DRY opportunity, missing edge case test.
- **nit** — style, comment polish, doc typo.
- **followup** — out of scope for this PR; should become a backlog issue, not a PR comment.

Hard caps:
- ≤ 15 comments per PR. If more, keep top 15 by severity, fold the rest into a single summary comment listing them.
- blocker/major MUST have file + line.

### 4. Post comments

For inline comments (any finding with `file` + `line`), use the GitHub review API in one batch:

```bash
gh api -X POST repos/lubobill1990/little-games/pulls/<pr>/reviews \
  -f event="<EVENT>" \
  -f body="<overall summary>" \
  -F commit_id="<headRefOid>" \
  -f "comments[][path]=..." -F "comments[][line]=..." -f "comments[][body]=..."
```

Where `<EVENT>`:
- Any `blocker` or `major` finding → `REQUEST_CHANGES` (then §4 plumbing: move issue to `Changes requested`, leave findings on PR for the author to address).
- Otherwise (only `minor` / `nit` / `followup`) → **don't post the inline comments here.** Skip directly to §4d, which rolls the non-blocking findings into the cleanup issue and auto-merges. Posting inline comments alongside an auto-merge produces dangling unresolved threads on the merged PR.

The "post inline comments + COMMENT event" path only runs implicitly inside §4d-step-1 when §4d has decided to merge — and even then, the comments are batched into the rolling cleanup issue's body rather than the PR (the PR is about to be merged; conversation belongs in the backlog issue).

For nits without a clear line on a `REQUEST_CHANGES` review, batch into the review `body` under a `### Nits` section.

For findings with a `suggestion`, the comment body should end with:

````
```suggestion
<suggestion>
```
````

**After posting a `REQUEST_CHANGES` review:** move the linked tracking issue (from §1) to `Changes requested` so the board reflects "author needs to iterate" rather than "still under review":

```bash
scripts/board.sh <linked_issue> ChangesRequested
```

This is also a CLAUDE.md hard rule (§5 Process #5). The author / `implement-task` skill is responsible for moving it back to `InReview` on their next push (and only when CI is green) — this skill never moves a `Changes requested` card forward.

**On a `REQUEST_CHANGES` review, do NOT touch the rolling cleanup issue.** §5b is *only* the no-finding-at-all backlink path now (the rolling-cleanup write is handled by §4d for the auto-merge case). For PRs that need changes, leave `minor` / `nit` findings as inline PR comments — `implement-task` will pick them up while fixing the blockers and decide what to roll into `Nit & minor cleanup` (see `implement-task` SKILL.md §11 for the contract).

### 4b. Auto-approve and auto-merge clean PRs (no findings at all)

If the review produced **zero findings of any severity** (no blocker / major / minor / nit / followup), the PR is eligible for auto-merge via this section.

If the review produced **only `minor` / `nit` / `followup` findings (no blocker / no major)**, the PR is still eligible for auto-merge — but goes through **§4d** instead of §4b. §4d batches the non-blocking findings into the rolling cleanup issue (and spins off `followup` items per §5) before merging.

If **any gate below fails** for an otherwise-eligible PR, post a plain `event=COMMENT` review with `body="No findings at <sha>."` (§4b case) or the §4d "rolled K findings into #N" message (§4d case) and STOP — do not merge.

**Gates** (all must pass):

1. PR is not a draft: `gh pr view <pr> --json isDraft --jq .isDraft` == `false`
2. CI is green:
   ```bash
   gh pr checks <pr> --repo lubobill1990/little-games
   ```
   All required checks `pass`. No `pending`, no `fail`.
3. No unresolved review threads from other reviewers:
   ```bash
   gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:50){nodes{isResolved}}}}}' \
     -F o=lubobill1990 -F r=little-games -F n=<pr> --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)'
   ```
   Must be empty.
4. PR author MUST be `weavejamtom` (the implement-task skill's identity). PRs from any other account — including `lubobill1990` herself or external contributors — always require human merge:
   ```bash
   gh pr view <pr> --json author --jq .author.login
   # Must equal: weavejamtom
   ```
5. The linked issue (from §1) is in Status=`In review`. If it's still `In progress`, author isn't done yet — skip merge.

**Action when all gates pass:**

```bash
# Approve via review API
gh api -X POST repos/lubobill1990/little-games/pulls/<pr>/reviews \
  -f event="APPROVE" \
  -f body="Auto-approved by gh-pr-review skill: no findings at <sha>, CI green, all gates passed." \
  -F commit_id="<headRefOid>"

# Squash merge (preserves clean main history per CLAUDE.md brevity contract)
gh pr merge <pr> --repo lubobill1990/little-games --squash --delete-branch
```

After merge:
- Move the linked issue to Done: `scripts/board.sh <issue> Done`
- Update state file with the merged sha so a re-run doesn't try again
- Note in summary: `#<pr> "<title>" → AUTO-MERGED (no findings)`

**Hard limits on auto-merge:**

- Never use `--admin` to bypass branch protection.
- Never auto-merge if any gate is uncertain (e.g., GraphQL call errored) — fail closed, post the comment, stop.
- Never auto-merge a PR authored by anyone other than `weavejamtom`. PRs by `lubobill1990` herself or external contributors are out of scope for auto-merge — comment "No findings at <sha>" and stop.
- Per run, auto-merge **at most 1 PR**, even if multiple are eligible. Forces human to notice the cadence.

### 4c. Human-override merge

When the user explicitly tells you to merge a PR despite a §4b gate failing (e.g., findings rolled into nit-cleanup, author isn't `weavejamtom`), this is a **human override** — proceed, but follow the same post-merge plumbing as §4b so the audit trail stays consistent.

Pre-flight (always check, even on override):

1. CI must still be green (`gh pr checks <pr>`). Override does not bypass red CI.
2. `GH_TOKEN` MUST still resolve to `lubobill1990` (verify with `gh api user --jq .login`). Since §0 exported it once per process, this should be a no-op; if it's empty or wrong, re-run the §Identity export block. Never approve / merge a PR while authenticated as its author — GitHub will reject self-approval and the audit trail will be muddled.
3. Any `blocker` or `major` finding still in play → STOP and report. Override is for non-blocking findings only.

Action:

```bash
# Approve, citing the override reason
gh api -X POST repos/lubobill1990/little-games/pulls/<pr>/reviews \
  -f event="APPROVE" \
  -F commit_id="<headRefOid>" \
  -f body="Approved by gh-pr-review skill (human override of §4b: <reason>)."

# Squash merge
gh pr merge <pr> --repo lubobill1990/little-games --squash --delete-branch

# Post-merge plumbing (same as §4b)
scripts/board.sh <linked_issue> Done
# Update .gh-pr-review-state.json with the merged sha
```

Note in summary: `#<pr> "<title>" → MERGED (human override: <reason>)`.

### 4d. Auto-merge with non-blocking findings (minor/nit/followup → cleanup issue)

Triggered when the review has **no `blocker` and no `major`** but produces ≥ 1 `minor` / `nit` / `followup`. Same gates as §4b (CI green, not draft, no foreign unresolved threads, author=`weavejamtom`, linked issue in `In review`); if any gate fails, fall back to posting a single `event=COMMENT` review with `body="No findings requiring changes at <sha>; gate <which> failed."` and STOP.

**Why this exists.** Posting `minor`/`nit` as inline `COMMENT` review threads on a PR we then auto-merge leaves dangling unresolved threads on the merged PR — noisy and wrong. Per CLAUDE.md brevity contract, non-blocking findings belong in the rolling cleanup backlog issue (§5b's existing pattern), not as merged-PR review threads. §4d enforces that flow automatically.

**Procedure** (do these in order; STOP and revert via §6 state-file rule if any step fails):

1. **Roll up `minor` / `nit` into the rolling cleanup issue** using §5b's full procedure — find/create the rolling issue, append the batch block, post backlinks on the PR + tracking issue. Capture the `<cleanup_issue_url>` and `<batch_url>` for the approval body.

2. **Spin off `followup` findings as scoped backlog issues** using §5's full procedure. Capture the new issue numbers for the approval body.

3. **Approve via the review API** (no inline comments — those went to the cleanup issue):

   ```bash
   gh api -X POST repos/lubobill1990/little-games/pulls/<pr>/reviews \
     -f event="APPROVE" \
     -F commit_id="<headRefOid>" \
     -f body="Auto-approved by gh-pr-review skill (§4d): <X> minor/nit rolled into <cleanup_issue_url>; <K> followup(s) spun off as #<n>, #<n>. CI green, all gates passed."
   ```

4. **Squash merge:**

   ```bash
   gh pr merge <pr> --repo lubobill1990/little-games --squash --delete-branch
   ```

5. **Post-merge plumbing** (identical to §4b):
   - Move the linked issue to Done: `scripts/board.sh <linked_issue> Done`
   - Update `.gh-pr-review-state.json` with `merged_commit` set to the new merge SHA so a re-run doesn't try again.

6. Note in summary: `#<pr> "<title>" → AUTO-MERGED (§4d): rolled <X> minor/nit into #<n>; spun off <K> followup(s) as #<m>, #<m>`.

**Hard limits (same as §4b):**

- Never `--admin` to bypass branch protection.
- Never auto-merge if a gate is uncertain — fail closed, post the diagnostic COMMENT review, stop.
- Never auto-merge a PR by anyone other than `weavejamtom`. External / `lubobill1990`-authored PRs always need human review of whether the cleanup-issue rollup is appropriate.
- Per run, auto-merge **at most 1 PR** total across §4b and §4d combined (forces human to notice cadence).
- Never run §4d if any finding is `blocker` or `major` — that path is `REQUEST_CHANGES` per §4, not auto-merge.

**The §4b decision tree summarized:**

```
findings ─┬─ contains blocker/major ─→ §4: REQUEST_CHANGES + move issue to Changes requested. STOP.
          ├─ all minor/nit/followup  ─→ §4d: roll into cleanup issue + §5 followup issues + auto-merge.
          └─ empty                    ─→ §4b: APPROVE + auto-merge.
```

### 5. Spin off `followup` findings as backlog issues

For each `followup` finding:

1. Create issue:
   ```bash
   gh issue create --repo lubobill1990/little-games \
     --title "<title>" \
     --label backlog \
     --body "$(cat <<'EOF'
   Spun off from PR #<pr> review.

   ## PRD
   _TBD — move to Ready before implementation._

   ## Dev plan
   _TBD._

   ## Context
   <body>

   Source: <permalink to file:line at headRefOid>
   EOF
   )"
   ```
2. Add to Project #5, set Status=Backlog and Priority:
   - Decide priority by reading existing backlog priorities:
     ```bash
     gh project item-list 5 --owner lubobill1990 --format json --limit 100
     ```
     Count current P0/P1/P2 in Backlog. Default to **P2** unless the finding text implies user-facing breakage / security / blocker-adjacent (then **P1**). Never auto-assign **P0** — leave that to the human; if you think it's P0, comment on the new issue saying so and set P1.
   - Add to project + set fields:
     ```bash
     # Add issue to project
     ITEM_ID=$(gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' -F p=PVT_kwHOAAnKBM4BWZYr -F c=<issue_node_id> --jq '.data.addProjectV2ItemById.item.id')

     # Set Status=Backlog
     gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' \
       -F p=PVT_kwHOAAnKBM4BWZYr -F i=$ITEM_ID -F f=PVTSSF_lAHOAAnKBM4BWZYrzhRuER4 -F o=c159f539

     # Set Priority (P2 example)
     gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' \
       -F p=PVT_kwHOAAnKBM4BWZYr -F i=$ITEM_ID -F f=PVTSSF_lAHOAAnKBM4BWZYrzhRuEWM -F o=da944a9c
     ```
   - `scripts/board.sh` is also fine for Status if preferred.

### 5b. Roll up `minor` / `nit` findings into the rolling cleanup issue

`minor` and `nit` findings are non-blocking but shouldn't evaporate after the PR closes. They're aggregated into a single rolling **"Nit & minor cleanup"** backlog issue, which a human (or the implement-task skill) periodically picks up.

**When this section runs.** §5b is now invoked exclusively as a sub-procedure of **§4d** (auto-merge with non-blocking findings). The standalone `event=COMMENT` path no longer exists — review event is always `REQUEST_CHANGES` (≥1 blocker/major), `APPROVE` (§4b/§4d), or no review at all (skipped SHA / no findings + gate failure → diagnostic COMMENT). When a `REQUEST_CHANGES` review fires, `minor` / `nit` findings stay inline on the PR (per §4 plumbing) — `implement-task` triages them on the fix pass.

**Rolling rule:** there is at most one *open, still-in-Backlog* cleanup issue at a time, identified by the label `nit-cleanup`. The moment that issue moves out of Backlog (a human/skill takes it → In progress / In review / Done, or it's closed), the next nit findings create a **new** cleanup issue. This way each batch maps to one work session.

**Procedure** — invoked by §4d-step-1 with the list of `minor` / `nit` findings.

1. Find the current rolling issue:

   ```bash
   # Open issues with label nit-cleanup, then filter to those still in Backlog on Project #5
   gh issue list --repo lubobill1990/little-games \
     --label nit-cleanup --state open --json number,title,projectItems --limit 20 \
     --jq '.[] | select(.projectItems[]? | .status.name == "Backlog") | .number' \
     | head -1
   ```

   (If `projectItems` shape differs, fall back to GraphQL using project node id `PVT_kwHOAAnKBM4BWZYr` and status field id `PVTSSF_lAHOAAnKBM4BWZYrzhRuER4` to filter for Backlog.)

2. Build the batch block (one block per PR per run):

   ```markdown
   ### From PR #<pr> @ <short_sha> — <YYYY-MM-DD>

   - [ ] **<file>:<line>** (<severity>) — <title>
     <body>
     [permalink](https://github.com/lubobill1990/little-games/blob/<headRefOid>/<file>#L<line>)
   - [ ] ... (one bullet per finding)
   ```

3a. **If a rolling issue exists** (step 1 returned a number): append the batch block as a comment.

   ```bash
   gh issue comment <existing_issue> --repo lubobill1990/little-games --body "$(cat batch.md)"
   ```

3b. **If no rolling issue exists**: create one.

   ```bash
   gh issue create --repo lubobill1990/little-games \
     --title "Nit & minor cleanup — batch starting <YYYY-MM-DD>" \
     --label nit-cleanup,backlog \
     --body "$(cat <<'EOF'
   Rolling collection of `minor` / `nit` findings spun off by the `gh-pr-review` skill. Pick up when convenient — each checkbox is independent and small.

   ## How this issue works

   - One open `nit-cleanup` issue lives in Backlog at any time.
   - Each PR review run that produces nits appends a new dated block below.
   - When this issue moves out of Backlog (someone starts it), the next review run opens a fresh cleanup issue.

   ## PRD
   _Not applicable — see individual checkboxes._

   ## Dev plan
   Work through bullets one at a time; small commits, conventional messages (`fix:`, `chore:`, `docs:` …). Close the issue when all boxes are checked OR drop remaining items into a new issue if scope balloons.

   ## Findings

   <batch block from step 2>
   EOF
   )"
   ```

   Then add the new issue to Project #5 with Status=`Backlog`, Priority=`P2` (using the GraphQL mutations from §5). Never escalate a cleanup issue's priority automatically.

4. **Capture the cross-links** so future readers can trace nit → cleanup-issue → batch-comment → PR.

   - For step 3a (appended to existing): grab the new comment's `html_url` from the `gh issue comment` output (or query `gh api repos/.../issues/<n>/comments --jq '.[-1].html_url'`). Call this `<batch_url>`. The `<cleanup_issue_url>` is `https://github.com/lubobill1990/little-games/issues/<existing_issue>`.
   - For step 3b (newly created): the cleanup issue itself is the batch — `<batch_url>` and `<cleanup_issue_url>` are the same URL returned by `gh issue create`.

5. **Backlink from PR and PR's tracking issue.** Post the same short note to both:

   ```bash
   NOTE="🧹 Rolled <K> minor/nit finding(s) from this review into the rolling cleanup issue: <cleanup_issue_url> (batch: <batch_url>)."

   # On the PR itself (general issue comment, not a review comment — survives if review is dismissed)
   gh issue comment <pr> --repo lubobill1990/little-games --body "$NOTE"

   # On the PR's tracking issue (the one in §1 that was in "In review")
   gh issue comment <linked_issue> --repo lubobill1990/little-games --body "$NOTE"
   ```

   Skip the second call if there's no linked tracking issue.

6. Note the rolling issue number in the summary line for this PR (`rolled <K> minor/nit into #<n>`).

**What still goes through §5 (separate `followup` issues), not here:**

- Anything tagged `severity: followup` in the JSON (out of scope for the PR, deserves its own scoped issue).
- Anything that needs a real PRD/Dev plan (a feature, a refactor with design decisions).

**What goes here:**

- Doc typos, naming, dead code, missing edge-case tests, style polish, small DRY ops, comment touch-ups, cross-platform script quirks, etc.

If unsure, prefer the rolling issue — it's cheaper to fold a borderline item in than to spawn a one-line scoped issue.

### 6. Update state and summarize

Write `.gh-pr-review-state.json` with the new `headRefOid` per PR. Then output a single summary block to the user:

```
Reviewed N PR(s):
  - #<pr> "<title>" → <EVENT>: <X blocker, Y major, Z minor, W nit>; rolled <Z+W> minor/nit into #<n>; spun off <K> followup(s) as #<n>, #<n>
Skipped M PR(s) (already reviewed at current SHA):
  - #<pr>
No linked PR for: <issue_numbers>
```

Be terse. No congratulations, no preamble.

## Style guardrails

- Inline comments: imperative voice, ≤ 3 lines unless quoting code. Example: `Untyped param. Add \`board: Board\` annotation per CLAUDE.md §5 code style.`
- Reference `CLAUDE.md` / `docs/*` sections by path when invoking a project rule.
- Never comment "LGTM" or approval praise. Clean PRs go through §4b (auto-merge if all gates pass) or get a tiny `body="No findings at <sha>."` comment if any gate fails.
- Never push commits. Never re-label the original issue's Status (other than moving to Done after a successful auto-merge per §4b).
- Don't review draft PRs (skip with note).
- If CI is red on the PR, mention it in the review body but still review the diff.

## 7. Local investigation via git worktree

**Default: stay remote.** `gh pr diff` + `gh api .../contents` cover most reviews. Only spin up a worktree when one of these is true:

- A **suspected blocker** needs cross-file context to confirm (e.g., "does anything else call this?")
- You want to **run tests** to verify a finding (`godot --headless ... gut_cmdln.gd`)
- You need to `Grep` the full repo at the PR's SHA

### Setup (per PR, on demand)

```bash
PR=<pr_number>
SHA=<headRefOid>
WT=.pr-review-worktrees/pr-$PR

# Concurrency lock — bail if another review is already in this worktree
if [ -e "$WT/.lock" ]; then
  echo "pr-$PR worktree busy, skipping local investigation"
  exit 0
fi

# Fetch the PR head into a per-PR ref (avoids polluting branch list)
git fetch origin "pull/$PR/head:refs/remotes/pr/$PR"

# Add detached worktree at the PR's head SHA
git worktree add --detach "$WT" "refs/remotes/pr/$PR"
mkdir -p "$WT" && touch "$WT/.lock"
```

### Use it (NEVER `cd`)

All commands use `-C` or `--path`:

```bash
git -C "$WT" log -1
git -C "$WT" grep "pattern"
godot --headless --path "$WT/godot" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

Reasoning: other agents may share this session's cwd. Changing directory breaks them.

### Teardown (always, even on failure)

```bash
rm -f "$WT/.lock"
git worktree remove --force "$WT"
git update-ref -d "refs/remotes/pr/$PR" 2>/dev/null || true
```

Wrap the investigation in a trap so teardown always runs:

```bash
trap 'rm -f "$WT/.lock"; git worktree remove --force "$WT" 2>/dev/null; git update-ref -d "refs/remotes/pr/$PR" 2>/dev/null' EXIT
```

### Inline comments still go through GitHub API

The worktree only enables local exploration. Review comments still POST to `repos/.../pulls/<pr>/reviews` with `commit_id=<headRefOid>` — the PR's remote SHA, not anything local.

## Failure modes

- `gh project item-list` returns no `status` → field name might differ; fall back to GraphQL using field id `PVTSSF_lAHOAAnKBM4BWZYrzhRuER4`.
- Linked PR is on a fork → inline comments still work; if the API rejects, fall back to a single general PR comment with all findings.
- Network / auth error → print the error and stop; do **not** mutate state file on partial runs.
- Worktree add fails (e.g., ref already checked out elsewhere) → skip local investigation, continue with remote-only review, note in summary.
- Stale `.lock` from a crashed previous run → if the worktree dir exists but no `git worktree list` entry references it, the §0 cleanup removes it.
