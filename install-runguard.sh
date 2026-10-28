#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build-dmg.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' RunGuard.app/Contents/Info.plist)
image="$PWD/dist/RunGuard-${version}-macos-arm64.dmg"
mountpoint=$(mktemp -d)
trap 'hdiutil detach "$mountpoint" -quiet >/dev/null 2>&1 || true; rmdir "$mountpoint" 2>/dev/null || true' EXIT
hdiutil attach "$image" -nobrowse -readonly -mountpoint "$mountpoint" >/dev/null

/usr/bin/pkill -TERM -x RunGuard 2>/dev/null || true
/bin/sleep 1
/usr/bin/osascript - "$mountpoint/RunGuard.app" <<'APPLESCRIPT'
on run argv
    set sourceApp to quoted form of (item 1 of argv)
    set installScript to quoted form of "/Applications/RunGuard.app/Contents/Resources/install-helper.sh"
    do shell script "/usr/bin/ditto " & sourceApp & " /Applications/RunGuard.app && /bin/bash " & installScript & " /Applications/RunGuard.app" with administrator privileges
end run
APPLESCRIPT
open /Applications/RunGuard.app
echo "Installed RunGuard.app in /Applications; the DMG is at $image"
