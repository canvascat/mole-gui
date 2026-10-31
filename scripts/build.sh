#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build/mole-gui.app/Contents/MacOS build/mole-gui.app/Contents/Resources
SOURCES=(Sources/MoleGUI/*.swift)

compile() {
  local target="$1"
  local output="$2"
  swiftc -parse-as-library \
    -sdk "$SDK" \
    -target "$target" \
    -swift-version 5 \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -o "$output" \
    "${SOURCES[@]}"
}

compile arm64-apple-macosx13.0 build/mole-gui-arm64
if compile x86_64-apple-macosx13.0 build/mole-gui-x64; then
  lipo -create -output build/mole-gui.app/Contents/MacOS/mole-gui build/mole-gui-arm64 build/mole-gui-x64
else
  cp build/mole-gui-arm64 build/mole-gui.app/Contents/MacOS/mole-gui
fi
rm -f build/mole-gui-arm64 build/mole-gui-x64
cp Info.plist build/mole-gui.app/Contents/Info.plist
codesign --force --sign - build/mole-gui.app
echo "built build/mole-gui.app"
