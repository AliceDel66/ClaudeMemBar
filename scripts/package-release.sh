#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d ' \t\r\n' < "$ROOT_DIR/VERSION")"
APP_NAME="ClaudeMemBar.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
RELEASE_DIR="$ROOT_DIR/dist/release"
STAGING_DIR="$ROOT_DIR/dist/package"
PACKAGE_DIR="$STAGING_DIR/ClaudeMemBar-$VERSION"
ZIP_PATH="$RELEASE_DIR/ClaudeMemBar-$VERSION-macOS.zip"
PKG_ROOT="$STAGING_DIR/pkgroot"
PKG_SCRIPTS="$STAGING_DIR/pkg-scripts"
PKG_PATH="$RELEASE_DIR/ClaudeMemBar-$VERSION.pkg"

"$ROOT_DIR/scripts/build.sh"

rm -rf "$RELEASE_DIR" "$STAGING_DIR"
mkdir -p "$RELEASE_DIR" "$PACKAGE_DIR" "$PKG_ROOT/Applications" "$PKG_SCRIPTS"

/usr/bin/ditto "$APP_DIR" "$PACKAGE_DIR/$APP_NAME"

cat > "$PACKAGE_DIR/install.command" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ClaudeMemBar.app"
APP_SOURCE="$SCRIPT_DIR/$APP_NAME"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/local.claude-mem-bar.plist"

if [ ! -d "$APP_SOURCE" ]; then
  echo "未找到 $APP_NAME，请确认 install.command 与 $APP_NAME 在同一目录。"
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/.claude-mem/logs"
/usr/bin/rsync -a --delete "$APP_SOURCE/" "$APP_PATH/"

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

/bin/launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl load "$PLIST_PATH"
/bin/launchctl kickstart -k "gui/$(id -u)/local.claude-mem-bar"

echo "ClaudeMemBar 已安装到 $APP_PATH"
echo "顶部菜单栏出现「记忆」后即可使用。"
INSTALL

cat > "$PACKAGE_DIR/uninstall.command" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/local.claude-mem-bar.plist"
APP_PATH="$HOME/Applications/ClaudeMemBar.app"

/bin/launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$APP_PATH"

echo "ClaudeMemBar 已卸载。"
UNINSTALL

cat > "$PACKAGE_DIR/INSTALL.txt" <<README
ClaudeMemBar $VERSION 安装说明

推荐方式：
1. 双击 install.command
2. 如果 macOS 提示无法打开，请右键 install.command，选择“打开”
3. 安装完成后，顶部菜单栏会出现“记忆”

卸载：
双击 uninstall.command

依赖：
- macOS 13 或更高版本
- Node.js（用于首次自动安装 claude-mem）

claude-mem 项目地址：
https://github.com/thedotmack/claude-mem
README

chmod +x "$PACKAGE_DIR/install.command" "$PACKAGE_DIR/uninstall.command"
/usr/bin/ditto -c -k --norsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

/usr/bin/ditto "$APP_DIR" "$PKG_ROOT/Applications/$APP_NAME"
cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/usr/bin/env bash
set -euo pipefail

LABEL="local.claude-mem-bar"
APP_PATH="/Applications/ClaudeMemBar.app"
CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console || true)"

if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
  exit 0
fi

USER_ID="$(/usr/bin/id -u "$CONSOLE_USER")"
USER_HOME="$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
PLIST_DIR="$USER_HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
LOG_DIR="$USER_HOME/.claude-mem/logs"

/bin/mkdir -p "$PLIST_DIR" "$LOG_DIR"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_PATH/Contents/MacOS/ClaudeMemBar</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/ClaudeMemBar.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/ClaudeMemBar.err.log</string>
</dict>
</plist>
PLIST

/usr/sbin/chown "$CONSOLE_USER":staff "$PLIST_PATH"
/bin/chmod 644 "$PLIST_PATH"
/usr/sbin/chown -R "$CONSOLE_USER":staff "$USER_HOME/.claude-mem" 2>/dev/null || true

/bin/launchctl bootout "gui/$USER_ID" "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$USER_ID" "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true

exit 0
POSTINSTALL

chmod +x "$PKG_SCRIPTS/postinstall"
/usr/bin/pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "local.claude-mem-bar" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_PATH"

cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<README
# ClaudeMemBar $VERSION

## 安装

推荐下载 \`ClaudeMemBar-$VERSION.pkg\`，双击安装即可。安装完成后，macOS 顶部菜单栏会出现「记忆」。

如果不想使用 pkg，也可以下载 \`ClaudeMemBar-$VERSION-macOS.zip\`，解压后运行其中的 \`install.command\`。

## 说明

- 首次运行如果未检测到 claude-mem，会自动执行 \`npx claude-mem@latest install\`。
- 依赖 Node.js 提供 \`npx\`。
- 菜单面板支持横向滑动切换系统页，展示本机状态与跨 Codex / Claude 来源的 Token 汇总。
- 温度读取依赖本机可用的 \`osx-cpu-temp\` 或 \`istats\`，不可用时会显示为“不可用”。
- claude-mem 项目地址：https://github.com/thedotmack/claude-mem

当前安装包未做 Apple notarization；如果 macOS 拦截，请在「系统设置 > 隐私与安全性」里允许打开。
README

echo "Created release assets:"
echo "  $ZIP_PATH"
echo "  $PKG_PATH"
