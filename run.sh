#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build --product TalkTimer
binary_dir=$(swift build --show-bin-path)
bundle="$PWD/.build/TalkTimer.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary_dir/TalkTimer" "$bundle/Contents/MacOS/TalkTimer"
cp Info.plist "$bundle/Contents/Info.plist"
if [[ "${1:-}" == --build-only ]]; then
  printf '%s\n' "$bundle"
else
  open "$bundle" --args "$@"
fi
