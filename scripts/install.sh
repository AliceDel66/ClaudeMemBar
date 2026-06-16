#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeMemBar.app"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/local.claude-mem-bar.plist"

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"
rsync -a --delete "$ROOT_DIR/dist/$APP_NAME/" "$APP_PATH/"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.claude-mem-bar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_PATH/Contents/MacOS/ClaudeMemBar</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/.claude-mem/logs/ClaudeMemBar.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.claude-mem/logs/ClaudeMemBar.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/local.claude-mem-bar"

echo "Installed $APP_PATH"
