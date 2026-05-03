# Pages bootstrap & branch protection

## Context

Issue #7 was moved to Done with red CI on `main` and an unreachable demo URL. Three consecutive `main` pushes (#34 [`d8df693`], #36 [`7d59e01`], #37) shipped red CI before manual remediation. Root cause: `actions/configure-pages@v5` defaults to `enablement: false`. The workflow looked correct on disk, but the repo had Pages disabled in settings — a state invisible from the workflow file. Compounding, the human merger merged each red PR without checking CI (CLAUDE.md §5 hard rule #4 violated three times). The skill-based reviewer (`gh-pr-review`) would have blocked on `gh pr checks`; the human did not.

Bootstrap was applied manually on 2026-05-03:
- `gh api -X POST repos/lubobill1990/little-games/pages -f build_type=workflow` enabled Pages with the Actions source.
- `gh run rerun 25275117590 --failed` brought `main` green and the site back up.

The site is live now, but **nothing in version control prevents the same failure on a fresh clone, fork, or accidental Pages-disable**, and **nothing prevents the human merger from again merging a red PR**.

## Solution

Three layers, all required:

1. **Workflow self-bootstraps Pages.** `actions/configure-pages` is invoked with `enablement: true` and **pinned to a commit SHA** (`983d7736d9b0ae728b81ab479565c72886d7745b`, the v5 tag at task-author time), not a floating tag. Floating tags can be re-pointed; the failure class we hit was "trusted setup-time state", and SHA pinning closes a similar door. `actions/deploy-pages` is also pinned (`d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e`, the v4 tag at the same instant). One known caveat: per the upstream action's `action.yml` description, `enablement: true` requires a token with `administration:write` scope — the default `GITHUB_TOKEN` lacks this. In our repo Pages is already enabled, so this step is a no-op for us; for a fresh fork, the bootstrap will fail loudly with a 403, which is strictly better than the prior silent "Get Pages site failed ... Not Found" error.

2. **Post-deploy verification, not just smoke.** After `actions/deploy-pages` succeeds, a step retries 12×10s checking three things in one pass:
   - `HEAD` on `index.html`, `index.wasm`, `index.pck` each returns `200` (catches partial-asset deploys),
   - `GET ${page_url}index.html` body contains a `<meta name="build-sha" content="...">` marker injected at build time,
   - the marker matches `${{ github.sha }}` (catches stale-CDN serving — the Pages CDN has been observed to take >30s to propagate).

3. **Branch protection on `main`.** Required status check: only the `ci / GUT (unit + integration)` job. Set via `gh api -X PUT .../branches/main/protection` after the PR merges (not a tracked file). Why only `test`: the `export-web` job is gated `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` — it never runs on PRs, so requiring it would make every PR un-mergeable. Deploy correctness is enforced by the post-deploy verification (mechanism 2) running **after** merge; if it fails on `main`, the failed run becomes visible on the next merge attempt because `strict=true` requires the PR's branch to be up to date with `main`. Acknowledged limitation: required-context names are matched as display strings — if anyone renames the workflow's `name:` fields, protection silently stops gating. One-line check in CLAUDE.md §5 is a future cleanup, not in scope here.

The general lesson: **any Action that depends on a repo-level toggle must set its auto-enable flag, or the job's first step must `gh api` the toggle and fail loudly with remediation steps.** Workflows that look correct on disk but silently depend on settings are the worst kind of CI bug — they pass review and fail on someone else's machine.
