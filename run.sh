#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building arm64…"
swift build -c release --triple arm64-apple-macosx

echo "Building x86_64…"
swift build -c release --triple x86_64-apple-macosx

echo "Creating universal binary…"
mkdir -p .build/universal
lipo -create \
  .build/arm64-apple-macosx/release/RandomGif \
  .build/x86_64-apple-macosx/release/RandomGif \
  -output .build/universal/RandomGif

APP="$HOME/Applications/RandomGif.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/universal/RandomGif "$APP/Contents/MacOS/RandomGif"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
xattr -cr "$APP"

pkill -f "RandomGif" 2>/dev/null || true
sleep 0.3
open "$APP"
echo "✓ Installed and running (universal + signed)"
