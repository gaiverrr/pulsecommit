#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/marketing-capture.sh"
VIDEO="$ROOT/marketing/video"
SCREENS="$VIDEO/public/screens"
SIM_NAME="${SIM_NAME:-iPhone 18 Pro}"
SIM_OS="${SIM_OS:-27.0}"
SKIP_CAPTURE=0

for arg in "$@"; do
  case "$arg" in
    --skip-capture) SKIP_CAPTURE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

for tool in node npm ffmpeg ffprobe; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

if [ "$SKIP_CAPTURE" -eq 0 ]; then
  marketing_capture "$ROOT" "$SIM_NAME" "$SIM_OS" PulseCommitMarketingUITests/HeroCaptureUITests "$SCREENS"
fi

for screen in 01-home-idle 02-home-running-a 03-home-running-b 04-home-running-c 05-home-done 06-history; do
  [ -f "$SCREENS/$screen.png" ] || { echo "missing $SCREENS/$screen.png - run without --skip-capture" >&2; exit 1; }
done

cd "$VIDEO"
[ -d node_modules ] || npm ci
npm run render
mkdir -p preview
cp out/hero-strip.jpg out/hero-wide-strip.jpg preview/

echo "==> outputs"
for file in out/hero.mp4 out/hero.webm out/hero-poster.jpg out/hero-wide.mp4 out/hero-wide.webm out/hero-wide-poster.jpg; do
  size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || echo "-")
  printf '%-22s %9s bytes  %ss\n' "$file" "$size" "$duration"
done
