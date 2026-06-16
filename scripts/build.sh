#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ClaudeMemBar.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

swiftc -O -framework AppKit \
  "$ROOT_DIR/Sources/ClaudeMemBar/main.swift" \
  -o "$MACOS_DIR/ClaudeMemBar"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$MACOS_DIR/ClaudeMemBar"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
