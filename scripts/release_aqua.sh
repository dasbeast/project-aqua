#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Tahoe.xcodeproj"
SCHEME="Aqua"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/AquaReleaseBuild}"
PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/Desktop/sparkle-private-key.txt}"
FEED_BASE_URL="${AQUA_FEED_BASE_URL:-https://baileykiehl.com/Aqua/}"
REMOTE_DIR="${AQUA_REMOTE_DIR:-public_html/Aqua}"
APPCAST_FILENAME="${AQUA_APPCAST_FILENAME:-appcast.xml}"
CODE_SIGN_IDENTITY="${AQUA_CODE_SIGN_IDENTITY:-Developer ID Application: Bailey Kiehl (4V28UB843Z)}"
NOTARY_PROFILE="${AQUA_NOTARY_PROFILE:-aqua-notary}"
SPARKLE_PUBLIC_ED_KEY="${AQUA_SPARKLE_PUBLIC_ED_KEY:-}"
SKIP_UPLOAD="${AQUA_SKIP_UPLOAD:-0}"
SU_FEED_URL="${AQUA_SU_FEED_URL:-${FEED_BASE_URL%/}/${APPCAST_FILENAME}}"
SSH_HOST="${AQUA_SSH_HOST:-baileyserver}"
SSH_USER="${AQUA_SSH_USER:-baileykiehl}"
SSH_KEY_FILE="${AQUA_SSH_KEY_FILE:-$HOME/.ssh/id_rsa}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release_aqua.sh

Required environment variables for release:
  AQUA_SPARKLE_PUBLIC_ED_KEY  Sparkle public Ed25519 key

Optional environment variables:
  AQUA_SSH_KEY_FILE           Path to SSH private key for uploads
  SPARKLE_PRIVATE_KEY_FILE    Path to your Sparkle private key export
  AQUA_FEED_BASE_URL          Public HTTPS base URL for release files
  AQUA_REMOTE_DIR             Remote directory on the server
  AQUA_APPCAST_FILENAME       Appcast filename to publish
  AQUA_CODE_SIGN_IDENTITY     Code signing identity used after plist injection
  AQUA_NOTARY_PROFILE         notarytool keychain profile name
  AQUA_SU_FEED_URL            Explicit SUFeedURL written into the app
  AQUA_SSH_HOST               SSH host for deployment
                               Default: baileyserver
  AQUA_SSH_USER               SSH username for deployment
                               Default: baileykiehl
  AQUA_SSH_KEY_FILE           Default: ~/.ssh/id_rsa
  AQUA_SKIP_UPLOAD            Set to 1 to build artifacts without uploading
  DERIVED_DATA_PATH           Override Xcode derived data path
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

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

sign_with_identity() {
  local target_path="$1"
  shift

  codesign \
    --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --options runtime \
    "$@" \
    "$target_path"
}

require_command xcodebuild
require_command ditto
require_command plutil
require_command scp
require_command ssh
require_command xmllint
require_command codesign
require_command xcrun

require_file "$PRIVATE_KEY_FILE"

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "Set AQUA_SPARKLE_PUBLIC_ED_KEY before running a release." >&2
  exit 1
fi

echo "Building $SCHEME..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
SPARKLE_BIN_DIR="$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"

require_file "$APP_PATH/Contents/MacOS/$SCHEME"
require_file "$INFO_PLIST"
require_file "$GENERATE_APPCAST"
require_file "$SIGN_UPDATE"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
RELEASE_DIR="$ROOT_DIR/release/Aqua-$SHORT_VERSION"
ZIP_FILENAME="Aqua-$SHORT_VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_FILENAME"
APPCAST_PATH="$RELEASE_DIR/$APPCAST_FILENAME"
LANDING_PAGE_SOURCE="$ROOT_DIR/index.html"
LANDING_PAGE_PATH="$RELEASE_DIR/index.html"
NOTARY_ZIP_PATH="/tmp/Aqua-$SHORT_VERSION-notarize.zip"
DOWNLOAD_PREFIX="${FEED_BASE_URL%/}/"

mkdir -p "$RELEASE_DIR"
require_file "$LANDING_PAGE_SOURCE"

echo "Injecting Sparkle keys into Aqua bundle..."
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUEnableInstallerLauncherService" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SU_FEED_URL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool YES" "$INFO_PLIST"

echo "Re-signing Sparkle helper components..."
sign_with_identity "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
sign_with_identity "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign_with_identity "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign_with_identity "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
sign_with_identity "$APP_PATH/Contents/Frameworks/Sparkle.framework"

echo "Re-signing Aqua.app..."
sign_with_identity \
  "$APP_PATH" \
  --entitlements "$ROOT_DIR/Tahoe/AquaRelease.entitlements"

echo "Creating notarization archive..."
rm -f "$NOTARY_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"

echo "Submitting for notarization..."
xcrun notarytool submit "$NOTARY_ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "Packaging Aqua $SHORT_VERSION ($BUILD_VERSION)..."
rm -f "$ZIP_PATH" "$APPCAST_PATH" "$LANDING_PAGE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
cp "$LANDING_PAGE_SOURCE" "$LANDING_PAGE_PATH"

echo "Generating appcast..."
"$GENERATE_APPCAST" \
  --ed-key-file "$PRIVATE_KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  -o "$APPCAST_FILENAME" \
  "$RELEASE_DIR"

if [[ ! -f "$APPCAST_PATH" ]]; then
  GENERATED_APPCAST="$(find "$RELEASE_DIR" -maxdepth 1 -name '*.xml' | head -n 1)"
  if [[ -z "${GENERATED_APPCAST:-}" && -f "$ROOT_DIR/$APPCAST_FILENAME" ]]; then
    GENERATED_APPCAST="$ROOT_DIR/$APPCAST_FILENAME"
  fi
  if [[ -n "${GENERATED_APPCAST:-}" && "$GENERATED_APPCAST" != "$APPCAST_PATH" ]]; then
    mv "$GENERATED_APPCAST" "$APPCAST_PATH"
  fi
fi

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "generate_appcast did not produce $APPCAST_PATH" >&2
  exit 1
fi

SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP_PATH" --ed-key-file "$PRIVATE_KEY_FILE")"
ED_SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
ARCHIVE_LENGTH="$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

if [[ -z "$ED_SIGNATURE" || -z "$ARCHIVE_LENGTH" ]]; then
  echo "Failed to extract Sparkle signature metadata from sign_update output." >&2
  exit 1
fi

if ! grep -q 'sparkle:edSignature=' "$APPCAST_PATH"; then
  perl -0pi -e 's#<enclosure url="([^"]+)" length="([^"]+)" type="application/octet-stream"/>#<enclosure url="$1" sparkle:edSignature="'"$ED_SIGNATURE"'" length="'"$ARCHIVE_LENGTH"'" type="application/octet-stream"/>#' "$APPCAST_PATH"
fi

xmllint --noout "$APPCAST_PATH"

echo
echo "Artifacts ready:"
echo "  $ZIP_PATH"
echo "  $APPCAST_PATH"
echo "  $LANDING_PAGE_PATH"

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo
  echo "Skipping upload because AQUA_SKIP_UPLOAD=1."
  exit 0
fi

REMOTE_TARGET="$SSH_USER@$SSH_HOST"
SSH_OPTIONS=()

if [[ -n "$SSH_KEY_FILE" ]]; then
  SSH_OPTIONS+=(-i "$SSH_KEY_FILE")
fi

echo
echo "Uploading release to $REMOTE_TARGET:$REMOTE_DIR ..."
ssh "${SSH_OPTIONS[@]}" "$REMOTE_TARGET" "mkdir -p '$REMOTE_DIR'"
scp "${SSH_OPTIONS[@]}" "$ZIP_PATH" "$APPCAST_PATH" "$LANDING_PAGE_PATH" "$REMOTE_TARGET:$REMOTE_DIR/"

echo
echo "Upload complete."
echo "Check these URLs:"
echo "  ${DOWNLOAD_PREFIX}index.html"
echo "  ${DOWNLOAD_PREFIX}${APPCAST_FILENAME}"
echo "  ${DOWNLOAD_PREFIX}${ZIP_FILENAME}"
