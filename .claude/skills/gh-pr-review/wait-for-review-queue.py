#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Block until at least one PR in the "In review" column has an unreviewed SHA.

Used by the `gh-pr-review` skill as a gate: the skill calls this first so it
only consumes Claude tokens when there's actual review work to do. Polls
`gh project item-list` every 30s. Reuses `.gh-pr-review-state.json` (written
by the skill) as the single source of truth for "already reviewed at SHA".

Exit codes:
  0 — work available; stdout is JSON {"prs": [{"issue": N, "pr": N, "sha": "..."}, ...]}
  2 — gh CLI / network error after retries (skill should surface and stop)
  130 — interrupted (Ctrl+C)
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

REPO = "lubobill1990/little-games"
PROJECT_OWNER = "lubobill1990"
PROJECT_NUMBER = "5"


def _repo_root() -> Path:
    res = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    if res.returncode != 0:
        print(f"[watch] not inside a git repo: {res.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return Path(res.stdout.strip())


STATE_FILE = _repo_root() / ".gh-pr-review-state.json"
POLL_SECONDS = 60
GH_RETRY_LIMIT = 3
GH_RETRY_BACKOFF = 5
ITEMS_PAGE_SIZE = 50

# One GraphQL hit gets: board items (status + linked content) + each
# linked PR's headRefOid. Replaces the old N+1 fan-out (project item-list →
# gh issue view → gh pr view per issue).
WORK_QUERY = """
query($owner:String!, $number:Int!, $first:Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      items(first: $first) {
        nodes {
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
          content {
            ... on Issue {
              number
              closedByPullRequestsReferences(first: 5, includeClosedPrs: false) {
                nodes { number state headRefOid }
              }
            }
          }
        }
      }
    }
  }
}
"""


def log(msg: str) -> None:
    print(f"[watch] {msg}", file=sys.stderr, flush=True)


def run_gh(args: list[str]) -> str:
    """Run a gh command with simple retry on transient failures."""
    last_err = ""
    for attempt in range(1, GH_RETRY_LIMIT + 1):
        try:
            res = subprocess.run(
                ["gh", *args],
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                return res.stdout
            last_err = res.stderr.strip() or res.stdout.strip()
        except FileNotFoundError:
            log("gh CLI not found on PATH")
            sys.exit(2)
        log(f"gh {' '.join(args[:2])} failed (attempt {attempt}/{GH_RETRY_LIMIT}): {last_err}")
        if attempt < GH_RETRY_LIMIT:
            time.sleep(GH_RETRY_BACKOFF)
    log(f"gh command exhausted retries: gh {' '.join(args)}")
    sys.exit(2)


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        log(f"state file unreadable ({e}); treating as empty")
        return {}


def in_review_prs() -> list[tuple[int, int, str]]:
    """One GraphQL call → list of (issue_number, pr_number, head_sha) for In review cards."""
    out = run_gh([
        "api", "graphql",
        "-f", f"query={WORK_QUERY}",
        "-F", f"owner={PROJECT_OWNER}",
        "-F", f"number={PROJECT_NUMBER}",
        "-F", f"first={ITEMS_PAGE_SIZE}",
    ])
    data = json.loads(out)
    nodes = (
        data.get("data", {}).get("user", {})
        .get("projectV2", {}).get("items", {}).get("nodes", [])
        or []
    )
    result: list[tuple[int, int, str]] = []
    for node in nodes:
        fv = node.get("fieldValueByName") or {}
        if fv.get("name") != "In review":
            continue
        content = node.get("content") or {}
        issue_num = content.get("number")
        if not isinstance(issue_num, int):
            continue
        prs = (content.get("closedByPullRequestsReferences") or {}).get("nodes") or []
        for pr in prs:
            if pr.get("state") != "OPEN":
                continue
            pr_num = pr.get("number")
            sha = pr.get("headRefOid")
            if isinstance(pr_num, int) and isinstance(sha, str) and sha:
                result.append((issue_num, pr_num, sha))
                break
    return result


def find_work() -> list[dict]:
    """Return list of {issue, pr, sha} for PRs whose head SHA has not been reviewed."""
    state = load_state()
    work: list[dict] = []
    for issue, pr_num, sha in in_review_prs():
        last = state.get(str(pr_num), {}).get("last_reviewed_sha")
        if last != sha:
            work.append({"issue": issue, "pr": pr_num, "sha": sha})
    return work


def log_active_identity() -> None:
    res = subprocess.run(
        ["gh", "api", "user", "--jq", ".login"],
        capture_output=True, text=True, check=False,
    )
    who = res.stdout.strip() if res.returncode == 0 else f"<unknown: {res.stderr.strip()}>"
    log(f"running as gh user: {who}")


def main() -> int:
    log_active_identity()
    log(f"polling every {POLL_SECONDS}s; state={STATE_FILE}")
    tick = 0
    while True:
        tick += 1
        try:
            work = find_work()
        except KeyboardInterrupt:
            return 130
        if work:
            log(f"tick {tick}: found {len(work)} PR(s) needing review")
            print(json.dumps({"prs": work}))
            return 0
        log(f"tick {tick}: queue empty, sleeping {POLL_SECONDS}s")
        try:
            time.sleep(POLL_SECONDS)
        except KeyboardInterrupt:
            return 130


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
