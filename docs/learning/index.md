# Learning log

Notes from mistakes that cost time. See CLAUDE.md §8 for the policy.

Format: `- [yyyy-mm-dd-slug.md](yyyy-mm-dd-slug.md) — <context>. <solution>.`

<!-- entries below, newest first -->
- [2026-05-03-pages-bootstrap.md](2026-05-03-pages-bootstrap.md) — `actions/configure-pages@v5` defaults to `enablement: false`; three red `main` runs landed before the failure was diagnosed because the workflow file gives no hint a repo setting is missing. Set `enablement: true`, pin actions to commit SHAs, add post-deploy asset+freshness check, and gate `main` with branch protection on `ci / GUT (unit + integration)`.
- [2026-05-03-gh-identity-lubobill1990.md](2026-05-03-gh-identity-lubobill1990.md) — gh CLI had two accounts active and defaulted to the wrong one for repo-owner ops. Use a process-scoped `GH_TOKEN` for `lubobill1990` and act autonomously for any GitHub operation in this repo.
