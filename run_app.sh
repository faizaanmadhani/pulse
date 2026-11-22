#!/bin/bash
# Pulse Training Native macOS Desktop Application Launcher

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$DIR/build/macos/Build/Products/Release/Pulse Training.app" ]; then
  echo "Launching Pulse Training (Release Build)..."
  open "$DIR/build/macos/Build/Products/Release/Pulse Training.app"
elif [ -d "$DIR/build/macos/Build/Products/Debug/Pulse Training.app" ]; then
  echo "Launching Pulse Training (Debug Build)..."
  open "$DIR/build/macos/Build/Products/Debug/Pulse Training.app"
else
  echo "App bundle not found. Building with Flutter..."
  /Users/faizaan/development/flutter/bin/flutter run -d macos
fi
