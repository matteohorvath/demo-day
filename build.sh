#!/bin/bash
# Builds Demo Day.app and installs it into ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Demo Day.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

if pgrep -x DemoDay >/dev/null 2>&1; then
  killall DemoDay || true
  sleep 0.3
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

clang \
  -fobjc-arc \
  -mmacosx-version-min=14.0 \
  -O2 \
  -Wall \
  -framework AppKit \
  -framework ServiceManagement \
  -o "$MACOS/DemoDay" \
  "$ROOT/Sources/main.m"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

python3 - "$RES" << 'PY'
import sys
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit(0)

out = Path(sys.argv[1])
iconset = out / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)
font_path = "/System/Library/Fonts/SFCompactRounded.ttf"
orange = (242, 101, 34, 255)

def render(px: int) -> Image.Image:
    im = Image.new("RGBA", (px, px), orange)
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(font_path, int(px * 0.62))
    text = "Y"
    box = draw.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    x = (px - tw) / 2 - box[0]
    y = (px - th) / 2 - box[1] - px * 0.02
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))
    return im

# iconutil names
specs = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
for name, px in specs.items():
    render(px).save(iconset / name)
print(f"iconset {iconset}")
PY

if [ -d "$RES/AppIcon.iconset" ]; then
  iconutil -c icns "$RES/AppIcon.iconset" -o "$RES/AppIcon.icns"
  rm -rf "$RES/AppIcon.iconset"
fi

codesign --force --deep --sign - --identifier "local.demoday.countdown" "$APP"

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Demo Day.app"
ditto "$APP" "$HOME/Applications/Demo Day.app"

echo "Installed: $HOME/Applications/Demo Day.app"
