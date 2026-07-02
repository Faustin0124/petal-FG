#!/usr/bin/env bash
set -euo pipefail

# Builds Petal for informal, internal sharing with collaborators — no Apple
# Developer account, no notarization. The app is ad-hoc signed (locally,
# with identity "-") so it runs on the machine that built it and on other
# Macs after the recipient bypasses Gatekeeper once (see instructions below).
#
# For an official signed + notarized release, use scripts/release/create-release.sh
# instead (requires Apple Developer Program credentials in secret_keys/).

SCHEME="petal"
PRODUCT_NAME="petal"
CONFIGURATION="Release"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build-adhoc"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"

XCODEBUILD=/usr/bin/xcodebuild

VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $(basename "$0") [--version X.Y.Z]"
      echo ""
      echo "Builds petal.app ad-hoc signed for internal sharing, then zips it."
      echo "Optionally overrides the marketing version (defaults to project setting)."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

VERSION_ARGS=()
if [[ -n "$VERSION" ]]; then
  VERSION_ARGS=(MARKETING_VERSION="$VERSION")
fi

echo "=== Building $PRODUCT_NAME ($CONFIGURATION, ad-hoc signed) ==="
$XCODEBUILD build \
  -project "$PROJECT_DIR/petal.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  "${VERSION_ARGS[@]}" \
  -quiet

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but $APP_PATH was not found." >&2
  exit 1
fi

RESOLVED_VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo dev)}"
ZIP_NAME="Petal-${RESOLVED_VERSION}-adhoc.zip"
ZIP_PATH="$PROJECT_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "=== Done ==="
echo "App:  $APP_PATH"
echo "Zip:  $ZIP_PATH"
echo ""
echo "Share the zip with collaborators. Since it isn't notarized, macOS Gatekeeper"
echo "will block it on first launch. Each collaborator needs to, once:"
echo "  1. Unzip and move petal.app to /Applications (or anywhere)."
echo "  2. Right-click (or Control-click) petal.app -> Open -> Open."
echo "     (Double-clicking will show a 'can't be opened' warning instead.)"
echo "  Alternatively: System Settings -> Privacy & Security -> 'Open Anyway'"
echo "  after the first blocked launch attempt."
