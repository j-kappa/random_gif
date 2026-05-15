# RandomGif

A macOS menu bar app that serves up random animated GIFs on demand. Click the sparkle icon in your menu bar, get a GIF, click it to copy to your clipboard.

## Features

- Lives in the menu bar — no Dock icon, no window clutter
- Fetches random GIFs from Reddit, random.dog, and The Cat API
- Preloads the next GIF in the background for instant display
- Click the GIF to copy it to your clipboard (file URL + raw GIF data)
- Click anywhere else to dismiss
- Smooth UI with vibrancy, rounded corners, and loading states

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode Command Line Tools

## Build & Run

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly
.build/release/RandomGif
```

## Install as App

The included `run.sh` script builds a release binary, packages it into a `.app` bundle at `~/Applications/RandomGif.app`, and launches it:

```bash
./run.sh
```

## Generate App Icon

Requires Python 3 and Pillow:

```bash
pip install pillow
python3 make_icon.py
```

This produces `AppIcon.icns` which `run.sh` copies into the app bundle.

## How It Works

The app picks a random GIF source (Reddit subreddits are weighted 3x vs. dog/cat APIs), downloads the image data, and renders it in a WebKit view using a custom URL scheme handler — no double-download, no temp files for display. When you click the GIF, it writes both a temporary file URL and the raw GIF pasteboard type so pasting works in most apps.

## Project Structure

```
Package.swift              # SPM manifest
Sources/RandomGif/
  main.swift               # App entry point
  AppDelegate.swift        # Menu bar item, panel show/hide
  GifFetcher.swift         # Reddit, dog, and cat API fetchers
  GifPreloader.swift       # Background preload actor
  GifWindowController.swift # Panel UI, WebKit view, clipboard
run.sh                     # Build + install script
make_icon.py               # Icon generator
```

## GIF Sources

- **Reddit** — shuffled selection from gif-focused subreddits (`/hot` JSON)
- **random.dog** — random dog GIFs
- **The Cat API** — random cat GIFs
