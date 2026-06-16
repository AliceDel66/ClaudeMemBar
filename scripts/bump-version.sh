#!/usr/bin/env bash
set -euo pipefail

# 发布脚本：自增 VERSION 并推送到 main，菜单栏应用检测到后会提示更新。
# 用法：
#   ./scripts/bump-version.sh            # patch +1（默认）
#   ./scripts/bump-version.sh minor      # minor +1，patch 归零
#   ./scripts/bump-version.sh major      # major +1，minor/patch 归零
#   ./scripts/bump-version.sh 1.4.2      # 指定具体版本号

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

current="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
IFS='.' read -r major minor patch <<< "$current"

bump="${1:-patch}"
case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  [0-9]*.[0-9]*.[0-9]*)
    major="${bump%%.*}"; rest="${bump#*.}"; minor="${rest%%.*}"; patch="${rest##*.}" ;;
  *)
    echo "用法: bump-version.sh [major|minor|patch|X.Y.Z]" >&2; exit 1 ;;
esac

next="$major.$minor.$patch"
printf '%s\n' "$next" > "$VERSION_FILE"
echo "版本号：$current → $next"

git -C "$ROOT_DIR" add VERSION
git -C "$ROOT_DIR" commit -m "发布 v$next"
git -C "$ROOT_DIR" push origin main

echo "已推送 v$next，菜单栏应用将在下次检查时提示更新。"
