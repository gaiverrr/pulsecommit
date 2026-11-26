#!/usr/bin/env bash
#
# make-hero-video.sh - capture app screens in the simulator and render the
# pulsecommit.app hero loop.
#
#   scripts/make-hero-video.sh                 capture + render
#   scripts/make-hero-video.sh --skip-capture  render from existing screens
#
# Outputs marketing/video/out/hero.mp4, hero.webm, hero-poster.jpg (1080x1920)
# and the 1440x1080 crop hero-wide.mp4, hero-wide.webm, hero-wide-poster.jpg,
# plus a one-frame-per-second strip for each (hero-strip.jpg, hero-wide-strip.jpg).
#
# Env: SIM_NAME (default "iPhone 18 Pro"), SIM_OS (default "27.0").

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO="$ROOT/marketing/video"
SCREENS="$VIDEO/public/screens"
SIM_NAME="${SIM_NAME:-iPhone 18 Pro}"
SIM_OS="${SIM_OS:-27.0}"
LOCK=/tmp/pulsecommit-xcodebuild.lock
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

capture() {
  command -v xcodegen >/dev/null || { echo "missing xcodegen (brew install xcodegen)" >&2; exit 1; }
  local work udid result
  work="$(mktemp -d)"
  result="$work/hero.xcresult"

  udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, os_version = sys.argv[1], sys.argv[2]
runtime_suffix = "iOS-" + os_version.replace(".", "-")
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if runtime.endswith(runtime_suffix):
        for device in devices:
            if device["name"] == name:
                print(device["udid"]); sys.exit(0)
sys.exit(1)
' "$SIM_NAME" "$SIM_OS")" || { echo "simulator '$SIM_NAME' on iOS $SIM_OS not found" >&2; exit 1; }

  echo "==> waiting for xcodebuild lock"
  until mkdir "$LOCK" 2>/dev/null; do sleep 20; done
  trap 'xcrun simctl status_bar "'"$udid"'" clear >/dev/null 2>&1 || true; rmdir "'"$LOCK"'" 2>/dev/null || true; rm -rf "'"$work"'"' EXIT

  (cd "$ROOT" && xcodegen generate --quiet)
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  echo "==> capturing screens on $SIM_NAME ($udid)"
  xcodebuild test \
    -project "$ROOT/PulseCommit.xcodeproj" \
    -scheme PulseCommitMarketing \
    -destination "id=$udid" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$result" \
    -quiet

  rm -rf "$work/attachments"
  xcrun xcresulttool export attachments --path "$result" --output-path "$work/attachments" >/dev/null
  rm -rf "$SCREENS"
  mkdir -p "$SCREENS"
  python3 - "$work/attachments" "$SCREENS" <<'PY'
import json, os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
copied = 0
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName", "")
        stem = name.split("_")[0] if "_" in name else os.path.splitext(name)[0]
        shutil.copy(os.path.join(src, item["exportedFileName"]), os.path.join(dst, stem + ".png"))
        copied += 1
if copied == 0:
    sys.exit("no attachments exported")
print(f"exported {copied} screens")
PY

  printf '{"date":"%s"}\n' "$(date +%F)" > "$SCREENS/meta.json"

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  rmdir "$LOCK" 2>/dev/null || true
  rm -rf "$work"
  trap - EXIT
}

if [ "$SKIP_CAPTURE" -eq 0 ]; then
  capture
fi

for screen in 01-home-idle 02-home-running-a 03-home-running-b 04-home-running-c 05-home-done 06-history; do
  [ -f "$SCREENS/$screen.png" ] || { echo "missing $SCREENS/$screen.png - run without --skip-capture" >&2; exit 1; }
done

cd "$VIDEO"
[ -d node_modules ] || npm ci
npm run render

echo "==> outputs"
for file in out/hero.mp4 out/hero.webm out/hero-poster.jpg out/hero-wide.mp4 out/hero-wide.webm out/hero-wide-poster.jpg; do
  size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || echo "-")
  printf '%-22s %9s bytes  %ss\n' "$file" "$size" "$duration"
done
