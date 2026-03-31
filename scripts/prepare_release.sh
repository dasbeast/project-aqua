#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Tahoe.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
SETTINGS_VIEW="$ROOT_DIR/Tahoe/UI/SettingsView.swift"
SCHEME="Aqua"
REMOTE_NAME="${AQUA_GIT_REMOTE:-origin}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prepare_release.sh <version> [--build <build-number>] [--no-push] [--no-tag]

Examples:
  ./scripts/prepare_release.sh 0.0.6
  ./scripts/prepare_release.sh 0.0.6 --build 7

What it does:
  - updates Xcode MARKETING_VERSION to the requested version
  - bumps CURRENT_PROJECT_VERSION (or uses --build)
  - updates the visible version footer in Settings
  - commits the version change on main
  - pushes main
  - creates and pushes tag v<version>

Options:
  --build <n>   Use an explicit build number instead of auto-incrementing
  --no-push     Commit locally but do not push main
  --no-tag      Commit locally but do not create/push the release tag
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Required file not found: $1" >&2
    exit 1
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

NEW_VERSION="$1"
shift

if [[ ! "$NEW_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Version must look like 0.0.5 or 1.2.3" >&2
  exit 1
fi

EXPLICIT_BUILD=""
PUSH_AFTER_COMMIT=1
CREATE_TAG=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      EXPLICIT_BUILD="${2:-}"
      shift 2
      ;;
    --no-push)
      PUSH_AFTER_COMMIT=0
      shift
      ;;
    --no-tag)
      CREATE_TAG=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$EXPLICIT_BUILD" && ! "$EXPLICIT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "--build must be an integer" >&2
  exit 1
fi

require_command git
require_command perl
require_command xcodebuild
require_file "$PROJECT_FILE"
require_file "$SETTINGS_VIEW"

cd "$ROOT_DIR"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Run this from the main branch." >&2
  echo "Current branch: $CURRENT_BRANCH" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

CURRENT_BUILD="$(
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings \
    | awk '/CURRENT_PROJECT_VERSION = / { print $3; exit }'
)"

if [[ -z "$CURRENT_BUILD" || ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Could not determine current build number." >&2
  exit 1
fi

if [[ -n "$EXPLICIT_BUILD" ]]; then
  NEW_BUILD="$EXPLICIT_BUILD"
else
  NEW_BUILD="$((CURRENT_BUILD + 1))"
fi

TAG_NAME="v$NEW_VERSION"

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "Tag already exists: $TAG_NAME" >&2
  exit 1
fi

perl -0pi -e 's/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = '"$NEW_VERSION"';/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = '"$NEW_BUILD"';/g' "$PROJECT_FILE"
perl -0pi -e 's/Aqua · v[0-9.]+ · Project Aqua/Aqua · v'"$NEW_VERSION"' · Project Aqua/g' "$SETTINGS_VIEW"

RESOLVED_VERSION="$(
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings \
    | awk '/MARKETING_VERSION = / { print $3; exit }'
)"
RESOLVED_BUILD="$(
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings \
    | awk '/CURRENT_PROJECT_VERSION = / { print $3; exit }'
)"

if [[ "$RESOLVED_VERSION" != "$NEW_VERSION" || "$RESOLVED_BUILD" != "$NEW_BUILD" ]]; then
  echo "Resolved Xcode version/build did not match requested values." >&2
  echo "Expected: $NEW_VERSION ($NEW_BUILD)" >&2
  echo "Resolved: $RESOLVED_VERSION ($RESOLVED_BUILD)" >&2
  exit 1
fi

git add "$PROJECT_FILE" "$SETTINGS_VIEW"
git commit -m "Release Aqua $NEW_VERSION build $NEW_BUILD"

if [[ "$PUSH_AFTER_COMMIT" == "1" ]]; then
  git push "$REMOTE_NAME" main
fi

if [[ "$CREATE_TAG" == "1" ]]; then
  git tag "$TAG_NAME"
  if [[ "$PUSH_AFTER_COMMIT" == "1" ]]; then
    git push "$REMOTE_NAME" "$TAG_NAME"
  fi
fi

echo
echo "Release prepared:"
echo "  Version: $NEW_VERSION"
echo "  Build:   $NEW_BUILD"
echo "  Commit:  $(git rev-parse --short HEAD)"
if [[ "$CREATE_TAG" == "1" ]]; then
  echo "  Tag:     $TAG_NAME"
fi
