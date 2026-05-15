#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP="$HOME/Applications/RandomGif.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/RandomGif "$APP/Contents/MacOS/RandomGif"
cp AppIcon.icns              "$APP/Contents/Resources/AppIcon.icns"
cp -f "$(dirname "$0")/Sources/../" 2>/dev/null || true

# Sync Info.plist from project copy if present
if [ -f Info.plist ]; then cp Info.plist "$APP/Contents/Info.plist"; fi

xattr -cr "$APP"
pkill -f "RandomGif" 2>/dev/null || true
sleep 0.3
open "$APP"
echo "✓ Installed and running"
