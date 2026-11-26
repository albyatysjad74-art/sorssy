#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"
OUTPUT_DIR="${1:-$ROOT/ios/build}"
DERIVED_DIR="${DERIVED_DATA_PATH:-$OUTPUT_DIR/DerivedData}"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required (install with: brew install xcodegen)" >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required; run this script on macOS with Xcode installed" >&2; exit 2; }

mkdir -p "$OUTPUT_DIR"
cd "$IOS_DIR"
xcodegen generate --spec project.yml
xcodebuild \
  -project Sorssy.xcodeproj \
  -scheme Sorssy \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DIR" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

APP_PATH="$DERIVED_DIR/Build/Products/Release-iphoneos/Sorssy.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle was not produced: $APP_PATH" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR/Payload"
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP_PATH" "$OUTPUT_DIR/Payload/Sorssy.app"
(
  cd "$OUTPUT_DIR"
  /usr/bin/zip -qry Sorssy-unsigned.ipa Payload
)
printf 'IPA_PATH=%s\n' "$OUTPUT_DIR/Sorssy-unsigned.ipa"
