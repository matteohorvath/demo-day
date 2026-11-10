#!/bin/bash
# Install Demo Day, a macOS menu-bar countdown.
#   curl -fsSL https://raw.githubusercontent.com/matteohorvath/demo-day/main/install.sh | bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Demo Day runs on macOS." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run this as your own user, without sudo. Demo Day installs into ~/Applications." >&2
  exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
  echo "The Xcode Command Line Tools are required (they include clang)." >&2
  echo "Install them, then run this again:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

REPO="matteohorvath/demo-day"
REF="${DEMO_DAY_REF:-main}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading Demo Day…"
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz" | tar -xz -C "$TMP"

SRC="$TMP/demo-day-${REF##*/}"
if [[ ! -f "$SRC/build.sh" ]]; then
  echo "Couldn't find the Demo Day source in the download." >&2
  exit 1
fi

bash "$SRC/build.sh"

# A piped download can mark the app as quarantined. Clear that so it opens.
xattr -cr "$HOME/Applications/Demo Day.app" 2>/dev/null || true

echo "Opening Demo Day…"
open "$HOME/Applications/Demo Day.app"
