#!/usr/bin/env python3
"""
Builds a styled DMG for RandomGif with:
  - Dark gradient background with subtle noise
  - App icon centered-left, Applications alias centered-right
  - Arrow between them
  - Custom volume icon
"""
import os, subprocess, sys, tempfile, shutil, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_PATH = os.path.expanduser("~/Applications/RandomGif.app")
ICON_PNG = os.path.join(SCRIPT_DIR, "icon.png")
ICNS_PATH = os.path.join(SCRIPT_DIR, "AppIcon.icns")
DMG_OUT = os.path.join(SCRIPT_DIR, "RandomGif.dmg")

BG_W, BG_H = 660, 400
ICON_SIZE = 128

def make_background():
    """Dark gradient background with the app icon, arrow, and Applications folder icon."""
    img = Image.new("RGBA", (BG_W, BG_H))
    draw = ImageDraw.Draw(img)

    top = (30, 30, 40)
    bottom = (18, 18, 24)
    for y in range(BG_H):
        t = y / (BG_H - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (BG_W - 1, y)], fill=(r, g, b, 255))

    subtitle_y = BG_H - 55
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
    except (OSError, IOError):
        font = ImageFont.load_default()

    text = "Drag RandomGif to Applications to install"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((BG_W - tw) / 2, subtitle_y), text, fill=(255, 255, 255, 200), font=font)

    arrow_y = BG_H // 2 - 10
    arrow_cx = BG_W // 2
    shaft_len = 50
    head_len = 14
    head_w = 10
    color = (255, 255, 255, 80)

    x0 = arrow_cx - shaft_len // 2
    x1 = arrow_cx + shaft_len // 2
    for dy in range(-1, 2):
        draw.line([(x0, arrow_y + dy), (x1 - head_len, arrow_y + dy)], fill=color)
    draw.polygon([
        (x1, arrow_y),
        (x1 - head_len, arrow_y - head_w),
        (x1 - head_len, arrow_y + head_w),
    ], fill=color)

    return img


def make_dmg():
    if not os.path.isdir(APP_PATH):
        print(f"App not found at {APP_PATH} — run ./run.sh first", file=sys.stderr)
        sys.exit(1)

    bg = make_background()

    staging = tempfile.mkdtemp(prefix="dmg_stage_")
    bg_dir = os.path.join(staging, ".background")
    os.makedirs(bg_dir)
    bg_path = os.path.join(bg_dir, "bg.png")
    bg.save(bg_path, "PNG")

    app_dest = os.path.join(staging, "RandomGif.app")
    shutil.copytree(APP_PATH, app_dest)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", app_dest], check=True)
    os.symlink("/Applications", os.path.join(staging, "Applications"))

    if os.path.exists(ICNS_PATH):
        shutil.copy2(ICNS_PATH, os.path.join(staging, ".VolumeIcon.icns"))

    if os.path.exists(DMG_OUT):
        os.remove(DMG_OUT)

    temp_dmg = DMG_OUT.replace(".dmg", "_temp.dmg")

    subprocess.run([
        "hdiutil", "create",
        "-volname", "RandomGif",
        "-srcfolder", staging,
        "-format", "UDRW",
        "-ov", temp_dmg
    ], check=True)

    mount = subprocess.run(
        ["hdiutil", "attach", temp_dmg, "-readwrite", "-noverify", "-noautoopen"],
        capture_output=True, text=True, check=True
    )
    dev_line = [l for l in mount.stdout.strip().split("\n") if "/Volumes/" in l]
    if not dev_line:
        print("Failed to mount DMG", file=sys.stderr)
        sys.exit(1)
    parts = dev_line[0].split("\t")
    dev = parts[0].strip()
    vol = parts[-1].strip()

    applescript = f'''
    tell application "Finder"
        tell disk "RandomGif"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {{100, 100, {100 + BG_W}, {100 + BG_H}}}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to {ICON_SIZE}
            set background picture of theViewOptions to file ".background:bg.png"
            set position of item "RandomGif.app" of container window to {{{BG_W // 2 - 130}, {BG_H // 2 - 30}}}
            set position of item "Applications" of container window to {{{BG_W // 2 + 130}, {BG_H // 2 - 30}}}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
    '''
    subprocess.run(["osascript", "-e", applescript], check=False)

    if os.path.exists(ICNS_PATH):
        subprocess.run(["SetFile", "-a", "C", vol], check=False)

    subprocess.run(["hdiutil", "detach", dev, "-quiet"], check=True)

    subprocess.run([
        "hdiutil", "convert", temp_dmg,
        "-format", "UDZO",
        "-imagekey", "zlib-level=9",
        "-o", DMG_OUT
    ], check=True)
    os.remove(temp_dmg)

    shutil.rmtree(staging)

    size = os.path.getsize(DMG_OUT) / (1024 * 1024)
    print(f"Done — {DMG_OUT} ({size:.1f} MB)")


if __name__ == "__main__":
    make_dmg()
