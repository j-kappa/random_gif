# RandomGif

<img src="assets/app_icon.png" width="128" alt="RandomGif icon">

A macOS menu bar app that serves up random animated GIFs on demand. Click the icon in your menu bar, get a GIF, click it to copy to your clipboard.

![RandomGif in action](assets/ad_01.png)

![Right-click menu](assets/ad_02.png)

Made by [John Kappa](https://johnkappa.com)

## Install

Download `RandomGif.dmg`, open it, and drag RandomGif to your Applications folder.

The app is ad-hoc signed but not notarized, so macOS will block it on first launch. To fix this, open Terminal and run:

```bash
xattr -cr /Applications/RandomGif.app
open /Applications/RandomGif.app
```

Requires **macOS 13 (Ventura)** or later. Universal binary — runs on both Apple Silicon and Intel Macs.

### Install via Terminal

Clone and build directly — requires Xcode Command Line Tools:

```bash
git clone https://github.com/j-kappa/random_gif.git
cd random_gif
cp .env.example .env        # then add your Giphy API key (optional)
./run.sh
```

This builds a universal binary, installs it to `~/Applications/RandomGif.app`, and launches it.

## Features

- Lives in the menu bar — no Dock icon, no window clutter
- Custom GIF logo in the menu bar
- Fetches random GIFs from Reddit, Giphy, random.dog, and The Cat API
- Preloads the next GIF in the background for instant display
- Click the GIF to copy it to your clipboard (file URL + raw GIF data)
- Click anywhere else to dismiss
- Right-click the menu bar icon for credits and quit
- Smooth UI with vibrancy, rounded corners, and loading states

## Giphy API Key (Optional)

To enable Giphy as a GIF source, get a free API key from [developers.giphy.com](https://developers.giphy.com) and add it to a `.env` file in the project root:

```bash
cp .env.example .env
```

Then edit `.env` and replace the placeholder:

```
GIPHY_API_KEY=your_actual_key_here
```

The build script injects the key at compile time. Without it, the app still works using Reddit, random.dog, and The Cat API.

## Build from Source

Requires Swift 5.9+ / Xcode Command Line Tools.

```bash
# Debug build
swift build

# Release build (single arch)
swift build -c release
```

## Install as App

The included `run.sh` builds a **universal binary** (arm64 + x86_64), packages it into a signed `.app` bundle at `~/Applications/RandomGif.app`, and launches it:

```bash
./run.sh
```

## Create DMG for Sharing

Requires Python 3 and Pillow:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pillow
python3 make_dmg.py
```

This produces `RandomGif.dmg` with a styled dark background, drag-to-install layout, and your custom volume icon.

## Generate App Icon

If you want to regenerate the procedural icon (instead of using `icon.png`):

```bash
source .venv/bin/activate
python3 make_icon.py
```

Or to convert a custom PNG to all required sizes:

```bash
mkdir -p AppIcon.iconset
sips -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png
# ... (see run.sh for all sizes)
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## How It Works

The app picks a random GIF source from a weighted pool (Reddit 3x, Giphy 2x, dog 1x, cat 1x), downloads the image data, and renders it in a WebKit view using a custom `giflocal://` URL scheme handler — no double-download, no temp files for display. When you click the GIF, it writes both a temporary file URL and the raw GIF pasteboard type so pasting works in most apps.

## Project Structure

```
Package.swift                # SPM manifest (macOS 13+, no dependencies)
Info.plist                   # App bundle metadata
Sources/RandomGif/
  main.swift                 # App entry point
  AppDelegate.swift          # Menu bar icon, right-click menu, credits
  GifFetcher.swift           # Reddit, Giphy, dog, and cat API fetchers
  Secrets.swift              # Generated from .env (git-ignored)
  GifPreloader.swift         # Background preload actor
  GifWindowController.swift  # Panel UI, WebKit view, clipboard, branding
run.sh                       # Build universal binary + install + sign
make_dmg.py                  # Create styled DMG for distribution
make_icon.py                 # Procedural icon generator
icon.png                     # Custom app icon source
GIF.svg                      # Menu bar icon SVG
.env.example                 # Template for API keys
```

## GIF Sources

- **Reddit** (weight 3) — shuffled selection from gif-focused subreddits (`/hot` JSON)
- **Giphy** (weight 2) — random GIFs via the Giphy API (requires API key)
- **random.dog** (weight 1) — random dog GIFs
- **The Cat API** (weight 1) — random cat GIFs
