#!/usr/bin/env bash
# scripts/board.sh — move a Project board card by issue number.
#
# Usage:
#   scripts/board.sh <issue-number> <Backlog|Ready|InProgress|InReview|Done>
#
# Why this script exists:
#   The CLAUDE.md task workflow requires Claude to keep the Project board in
#   sync at every transition. Hand-running the GraphQL `gh project item-edit`
#   incantation every time is error-prone. This script wraps it.

set -euo pipefail

PROJECT_OWNER="lubobill1990"
PROJECT_NUMBER=5
PROJECT_ID="PVT_kwHOAAnKBM4BWZYr"
STATUS_FIELD_ID="PVTSSF_lAHOAAnKBM4BWZYrzhRuER4"

declare -A STATUS_OPTION=(
  [Backlog]="f75ad846"
  [Ready]="61e4505c"
  [InProgress]="47fc9ee4"
  [InReview]="df73e18b"
  [Done]="98236657"
)

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <issue-number> <Backlog|Ready|InProgress|InReview|Done>" >&2
  exit 2
fi

ISSUE_NUMBER="$1"
TARGET_STATUS="$2"

OPTION_ID="${STATUS_OPTION[$TARGET_STATUS]:-}"
if [[ -z "$OPTION_ID" ]]; then
  echo "Unknown status '$TARGET_STATUS'. Choose: ${!STATUS_OPTION[*]}" >&2
  exit 2
fi

ITEM_ID=$(gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        items(first: 100) {
          nodes {
            id
            content { ... on Issue { number } }
          }
        }
      }
    }
  }' -F owner="$PROJECT_OWNER" -F number=$PROJECT_NUMBER \
  --jq ".data.user.projectV2.items.nodes[] | select(.content.number==$ISSUE_NUMBER) | .id")

if [[ -z "$ITEM_ID" || "$ITEM_ID" == "null" ]]; then
  echo "Issue #$ISSUE_NUMBER not found on project $PROJECT_NUMBER." >&2
  exit 1
fi

gh project item-edit \
  --project-id "$PROJECT_ID" \
  --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID" >/dev/null

echo "✓ Issue #$ISSUE_NUMBER → $TARGET_STATUS"
