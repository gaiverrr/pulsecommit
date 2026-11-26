#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/marketing-capture.sh"
VIDEO="$ROOT/marketing/video"
SCREENS="$VIDEO/public/store"
OUT="$ROOT/marketing/screenshots/out"
SHEET="$ROOT/marketing/screenshots/preview/contact-sheet.jpg"
SIM_NAME="${SIM_NAME:-iPhone 18 Pro Max}"
SIM_OS="${SIM_OS:-27.0}"
SKIP_CAPTURE=0

for arg in "$@"; do
  case "$arg" in
    --skip-capture) SKIP_CAPTURE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

for tool in node npm ffmpeg ffprobe sips; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

if [ "$SKIP_CAPTURE" -eq 0 ]; then
  marketing_capture "$ROOT" "$SIM_NAME" "$SIM_OS" PulseCommitMarketingUITests/StoreCaptureUITests "$SCREENS"
fi

for screen in store-home store-history store-destinations store-webhook store-automate; do
  [ -f "$SCREENS/$screen.png" ] || { echo "missing $SCREENS/$screen.png - run without --skip-capture" >&2; exit 1; }
done

cd "$VIDEO"
[ -d node_modules ] || npm ci
npm run render:store

echo "==> checks"
failed=0
count=0
for file in "$OUT"/*.png; do
  count=$((count + 1))
  info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$file")"
  echo "$info"
  width=$(awk '/pixelWidth/ {print $2}' <<<"$info")
  height=$(awk '/pixelHeight/ {print $2}' <<<"$info")
  alpha=$(awk '/hasAlpha/ {print $2}' <<<"$info")
  if [ "$width" != 1320 ] || [ "$height" != 2868 ] || [ "$alpha" != no ]; then
    echo "FAIL $file: ${width}x${height} alpha=$alpha" >&2
    failed=1
  fi
done
[ "$count" -eq 6 ] || { echo "FAIL expected 6 screenshots, found $count" >&2; failed=1; }
sheet_bytes=$(stat -f%z "$SHEET" 2>/dev/null || stat -c%s "$SHEET")
echo "$SHEET $sheet_bytes bytes"
[ "$sheet_bytes" -lt 409600 ] || { echo "FAIL contact sheet is 400 KB or more" >&2; failed=1; }
exit "$failed"
