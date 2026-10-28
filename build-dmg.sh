#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build-app.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' RunGuard.app/Contents/Info.plist)
image="dist/RunGuard-${version}-macos-arm64.dmg"
mkdir -p dist
hdiutil create -volname RunGuard -srcfolder RunGuard.app -ov -format UDZO "$image"
echo "Built $PWD/$image"
