---
name: GitHub identity for this repo
description: Default to lubobill1990 for any gh / GitHub API operation in this repo; do not ask the user to run things manually.
type: feedback
---

# Context

`gh auth status` on this machine shows two accounts: `weavejamtom` (the implementer-skill identity) and `lubobill1990` (the repo owner). The active one was `weavejamtom`, so commands like `gh api repos/lubobill1990/little-games/pages` ran as the wrong user and either hit 404 or lacked permission to enable Pages, repo settings, etc.

# Solution

For any GitHub operation against `lubobill1990/little-games` (enabling Pages, editing repo settings, dispatching workflows, creating releases, opening PRs from the owner's perspective, …):

1. Run `gh auth switch --user lubobill1990` first if not already active. Verify with `gh auth status | head -5`.
2. Then proceed with the operation directly — **do not** ask the user to do it manually in the browser or via `! gh ...`. The user has authorized this identity and explicitly wants Claude to act as `lubobill1990` autonomously.
3. The `weavejamtom` identity is reserved for the `implement-task` skill (claiming Ready tasks). Don't switch back unless that skill is running.

**Why:** user said "为了 web deploy 正确性，你帮我直接用 lubobill1990 的身份操作 ... 后续需要用 lubobill1990 的身份进行 github 操作时，都自主操作，而不需要让我手动来" (2026-05-03). Asking them to click through GitHub Settings UI defeats the point of having the token.

**How to apply:** before any `gh` / GitHub API call in this repo, check active account; switch to `lubobill1990` if needed; execute. Skip confirmation for read ops and routine writes (Pages enable, workflow rerun, label edits). Still confirm before destructive ops (delete repo, force-push to main, delete branches with unmerged work) per the global "executing actions with care" rule.
