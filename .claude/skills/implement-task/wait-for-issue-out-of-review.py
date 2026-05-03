#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Block until a given Project #5 issue leaves the "In review" column.

Used by the `implement-task` skill as a serialization gate: after pushing a PR,
the skill records the issue number in `.implement-task-state.json` under
`pending_review.issue`. On the next tick, before scanning Ready tasks (§2),
the skill calls this script with that issue number. The script polls every 30s
and only returns when the card is no longer in `In review` (typically: moved to
`Changes requested` by the reviewer, or `Done` after merge).

Usage:
    wait-for-issue-out-of-review.py <issue_number>

Exit codes:
  0 — issue is no longer in In review; stdout is JSON {"issue": N, "status": "<new>"}
  2 — gh CLI / network error after retries (skill should surface and stop)
  3 — bad arguments
  130 — interrupted (Ctrl+C)
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

PROJECT_OWNER = "lubobill1990"
PROJECT_NUMBER = "5"
POLL_SECONDS = 60
GH_RETRY_LIMIT = 3
GH_RETRY_BACKOFF = 5
ITEMS_PAGE_SIZE = 50

# One GraphQL hit returns every card's status + linked issue number, so we can
# locate the watched issue's status without `gh project item-list --limit 100`
# (which pulls every field value on the board).
STATUS_QUERY = """
query($owner:String!, $number:Int!, $first:Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      items(first: $first) {
        nodes {
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
          content {
            ... on Issue { number }
          }
        }
      }
    }
  }
}
"""


def log(msg: str) -> None:
    print(f"[wait-review] {msg}", file=sys.stderr, flush=True)


def run_gh(args: list[str]) -> str:
    last_err = ""
    for attempt in range(1, GH_RETRY_LIMIT + 1):
        try:
            res = subprocess.run(
                ["gh", *args],
                capture_output=True, text=True, check=False,
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


def status_of(issue: int) -> str | None:
    """Return the Project #5 status name for `issue`, or None if not on the board."""
    out = run_gh([
        "api", "graphql",
        "-f", f"query={STATUS_QUERY}",
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
    for node in nodes:
        content = node.get("content") or {}
        if content.get("number") != issue:
            continue
        fv = node.get("fieldValueByName") or {}
        return fv.get("name")
    return None


def log_active_identity() -> None:
    res = subprocess.run(
        ["gh", "api", "user", "--jq", ".login"],
        capture_output=True, text=True, check=False,
    )
    who = res.stdout.strip() if res.returncode == 0 else f"<unknown: {res.stderr.strip()}>"
    log(f"running as gh user: {who}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wait-for-issue-out-of-review.py <issue_number>", file=sys.stderr)
        return 3
    try:
        issue = int(sys.argv[1])
    except ValueError:
        print(f"issue number must be an integer, got: {sys.argv[1]}", file=sys.stderr)
        return 3

    log_active_identity()
    log(f"watching issue #{issue}; polling every {POLL_SECONDS}s")
    tick = 0
    while True:
        tick += 1
        try:
            status = status_of(issue)
        except KeyboardInterrupt:
            return 130
        if status != "In review":
            shown = status if status is not None else "(not on board)"
            log(f"tick {tick}: issue #{issue} is now '{shown}', returning")
            print(json.dumps({"issue": issue, "status": status}))
            return 0
        log(f"tick {tick}: still In review, sleeping {POLL_SECONDS}s")
        try:
            time.sleep(POLL_SECONDS)
        except KeyboardInterrupt:
            return 130


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
