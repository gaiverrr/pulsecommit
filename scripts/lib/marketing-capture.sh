#!/usr/bin/env bash

MARKETING_LOCK=/tmp/pulsecommit-xcodebuild.lock

marketing_capture() {
  local root="$1" sim_name="$2" sim_os="$3" only_testing="$4" dest="$5"
  command -v xcodegen >/dev/null || { echo "missing xcodegen (brew install xcodegen)" >&2; exit 1; }
  local work udid result
  work="$(mktemp -d)"
  result="$work/capture.xcresult"

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
' "$sim_name" "$sim_os")" || { echo "simulator '$sim_name' on iOS $sim_os not found" >&2; exit 1; }

  echo "==> waiting for xcodebuild lock"
  until mkdir "$MARKETING_LOCK" 2>/dev/null; do sleep 20; done
  trap 'xcrun simctl status_bar "'"$udid"'" clear >/dev/null 2>&1 || true; rmdir "'"$MARKETING_LOCK"'" 2>/dev/null || true; rm -rf "'"$work"'"' EXIT

  (cd "$root" && xcodegen generate --quiet)
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  echo "==> capturing $only_testing on $sim_name ($udid)"
  xcodebuild test \
    -project "$root/PulseCommit.xcodeproj" \
    -scheme PulseCommitMarketing \
    -destination "id=$udid" \
    -only-testing:"$only_testing" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$result" \
    -quiet

  rm -rf "$work/attachments"
  xcrun xcresulttool export attachments --path "$result" --output-path "$work/attachments" >/dev/null
  rm -rf "$dest"
  mkdir -p "$dest"
  python3 - "$work/attachments" "$dest" <<'PY'
import json, os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
copied = 0
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName", "")
        exported = item["exportedFileName"]
        stem = name.split("_")[0] if "_" in name else os.path.splitext(name)[0]
        ext = os.path.splitext(exported)[1] or ".png"
        shutil.copy(os.path.join(src, exported), os.path.join(dst, stem + ext))
        copied += 1
if copied == 0:
    sys.exit("no attachments exported")
print(f"exported {copied} screens")
PY

  printf '{"date":"%s"}\n' "$(date +%F)" > "$dest/meta.json"

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  rmdir "$MARKETING_LOCK" 2>/dev/null || true
  rm -rf "$work"
  trap - EXIT
}
