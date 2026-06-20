#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Airwang DIT for Mac"
PROJECT_NAME="Airwang DIT for Mac.xcodeproj"
SCHEME_NAME="Airwang DIT for Mac"
CONFIGURATION="Debug"
BUNDLE_ID="com.airwang.ditformac.dev"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.derivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -z "${DEVELOPER_DIR:-}" ]] && ! /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1; then
  if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

kill_running_app() {
  pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
}

build_app() {
  /usr/bin/xcrun xcodebuild \
    -project "$ROOT_DIR/$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination "platform=macOS" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  sleep 2
  pgrep -f "$APP_BINARY" >/dev/null
}

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

kill_running_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_app
    ;;
  *)
    usage
    exit 2
    ;;
esac
