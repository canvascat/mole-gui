#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/mole-gui.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 多个 --arch 一起编需要完整 Xcode；只有 Command Line Tools 时退回只编 arm64。
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}"; then
  ARCHS=(--arch arm64)
  swift build -c release "${ARCHS[@]}"
fi
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/mole-gui" "$APP/Contents/MacOS/mole-gui"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built $APP"
