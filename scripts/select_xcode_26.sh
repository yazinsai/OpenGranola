#!/usr/bin/env bash
set -euo pipefail

xcode_app="$(
  find /Applications -maxdepth 1 -type d -name 'Xcode_26*.app' | sort | tail -n 1
)"

if [[ -n "${xcode_app:-}" ]]; then
  developer_dir="$xcode_app/Contents/Developer"
elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  developer_dir="/Applications/Xcode.app/Contents/Developer"
else
  echo "Unable to locate Xcode in /Applications" >&2
  exit 1
fi

sudo xcode-select -s "$developer_dir"
echo "Selected developer directory: $developer_dir"
xcodebuild -version
swift --version
