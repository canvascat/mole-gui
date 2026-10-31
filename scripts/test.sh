#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -swift-version 5 \
  -o build/mole-gui-tests \
  Sources/MoleGUI/CommandPolicy.swift \
  Sources/MoleGUI/Formatting.swift \
  Sources/MoleGUI/Models.swift \
  Sources/MoleGUI/TerminalText.swift \
  Sources/MoleGUI/MoleLocator.swift \
  Sources/MoleGUI/ProcessRunner.swift \
  Tests/main.swift
./build/mole-gui-tests
