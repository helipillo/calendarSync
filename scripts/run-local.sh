#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CalendarBridge.xcodeproj"
SCHEME="CalendarBridge"
DERIVED_DATA_PATH="$ROOT_DIR/build"
CONFIGURATION="Release"
CODE_SIGNING_ALLOWED="NO"

usage() {
  cat <<'EOF'
Usage: ./scripts/run-local.sh [--debug] [--signed] [--help]

Builds CalendarBridge locally and launches the built app.

Options:
  --debug   Build Debug instead of Release
  --signed  Allow code signing during the build
  --help    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="Debug"
      shift
      ;;
    --signed)
      CODE_SIGNING_ALLOWED="YES"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is not installed or not on PATH" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "error: Xcode project not found at $PROJECT_PATH" >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/CalendarBridge.app"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Launching $APP_PATH"
open "$APP_PATH"
echo "CalendarBridge launched. Look for the menu bar icon at the top right of your screen."
