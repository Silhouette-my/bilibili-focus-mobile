#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BilibiliFocus"
BUILD_DIR="$ROOT_DIR/build/dist"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.tmp-ipa-build-XXXXXX")"
DERIVED_DATA_PATH="$WORK_DIR/DerivedData"
PAYLOAD_DIR="$WORK_DIR/Payload"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/${APP_NAME}.app"
IPA_PATH="$BUILD_DIR/${APP_NAME}-unsigned.ipa"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$PAYLOAD_DIR"

xcodebuild \
  -project "$ROOT_DIR/BilibiliFocus.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

cp -R "$APP_PATH" "$PAYLOAD_DIR/"

(
  cd "$WORK_DIR"
  COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc Payload "$IPA_PATH"
)

printf 'Created unsigned IPA at %s\n' "$IPA_PATH"
