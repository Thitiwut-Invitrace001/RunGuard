#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release

app="$PWD/RunGuard.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/PrivilegedHelperTools" "$app/Contents/Resources"
cp .build/release/RunGuardApp "$app/Contents/MacOS/RunGuard"
cp .build/release/runguard-cli "$app/Contents/MacOS/runguard-cli"
cp .build/release/RunGuardHelper "$app/Contents/Library/PrivilegedHelperTools/com.runguard.helper"
cp Resources/install-helper.sh "$app/Contents/Resources/install-helper.sh"
chmod 755 "$app/Contents/Resources/install-helper.sh"
cp Resources/Info.plist "$app/Contents/Info.plist"
echo "Built $app"
