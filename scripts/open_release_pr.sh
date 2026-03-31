#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BASE_BRANCH="${AQUA_PR_BASE:-main}"
HEAD_BRANCH="${AQUA_PR_HEAD:-dev}"
TITLE="${AQUA_PR_TITLE:-Release: merge dev into main}"
BODY_FILE="$(mktemp)"

cleanup() {
  rm -f "$BODY_FILE"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command gh

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated." >&2
  echo "Run: gh auth login -h github.com" >&2
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$HEAD_BRANCH" ]]; then
  echo "Switch to '$HEAD_BRANCH' before opening the release PR." >&2
  echo "Current branch: $current_branch" >&2
  exit 1
fi

cat > "$BODY_FILE" <<EOF
## Release PR

- Source branch: \`$HEAD_BRANCH\`
- Target branch: \`$BASE_BRANCH\`

This PR is intended to merge the current development work into the stable release branch for Aqua.
EOF

gh pr create \
  --base "$BASE_BRANCH" \
  --head "$HEAD_BRANCH" \
  --title "$TITLE" \
  --body-file "$BODY_FILE"
