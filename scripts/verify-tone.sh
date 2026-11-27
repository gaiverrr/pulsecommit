#!/usr/bin/env bash
#
# verify-tone.sh — fail if any user-facing copy uses forbidden marketing-speak.
#
# Scans user-facing source trees:
#   PulseCommit/                       Swift sources for app strings
#   Packages/HealthCore/Sources/       error strings surfaced to History UI
#   docs/legal/                        hosted policy markdown
#   docs/store/                        App Store Connect metadata
#   marketing/video/src/               hero animation copy
#
# Exits 0 if clean, 1 if any forbidden word is found.

set -euo pipefail

cd "$(dirname "$0")/.."

WORDS=(
  seamless
  revolutionary
  magical
  unleash
  "transform your"
  "your data your way"
  cutting-edge
  "harness the power"
  "take control of your"
  powerful
  effortless
  delight
  delightful
  craft
  crafted
)

PATHS=(
  PulseCommit
  Packages/HealthCore/Sources
  docs/legal
  docs/store
  marketing/video/src
)

hits=0
for word in "${WORDS[@]}"; do
  pattern="\\b${word}\\b"
  if matches=$(grep -RInE --binary-files=without-match -i \
        --exclude-dir=.git \
        --exclude-dir=.build \
        --exclude='*.xcodeproj' \
        "${pattern}" "${PATHS[@]}" 2>/dev/null); then
    echo "forbidden tone word '${word}':"
    echo "${matches}"
    echo
    hits=$((hits + 1))
  fi
done

if [ "${hits}" -gt 0 ]; then
  echo "verify-tone: ${hits} forbidden term(s) present"
  exit 1
fi

echo "verify-tone: clean"
exit 0
