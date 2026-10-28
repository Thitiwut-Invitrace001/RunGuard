#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release

app="$PWD/RunGuard.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/RunGuard "$app/Contents/MacOS/RunGuard"
cp .build/release/runguard "$app/Contents/MacOS/runguard"
cp Resources/Info.plist "$app/Contents/Info.plist"
echo "Built $app"
