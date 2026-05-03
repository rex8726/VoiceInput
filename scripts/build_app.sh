#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/VoiceInput.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp ".build/release/VoiceInput" "$MACOS_DIR/VoiceInput"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
