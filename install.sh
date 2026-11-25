#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/Thitiwut-Invitrace001/RunGuard/main/install.sh | bash
set -euo pipefail

repo="Thitiwut-Invitrace001/RunGuard"
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { echo "RunGuard requires macOS on Apple Silicon" >&2; exit 1; }

work=$(mktemp -d)
mountpoint="$work/mnt"
trap 'hdiutil detach "$mountpoint" -quiet >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

echo "Downloading RunGuard..."
curl -fsSL -o "$work/RunGuard.dmg" "https://github.com/$repo/releases/latest/download/RunGuard-macos-arm64.dmg"
mkdir "$mountpoint"
hdiutil attach "$work/RunGuard.dmg" -nobrowse -readonly -mountpoint "$mountpoint" >/dev/null

/usr/bin/pkill -TERM -x RunGuard 2>/dev/null || true
rm -rf /Applications/RunGuard.app
/usr/bin/ditto "$mountpoint/RunGuard.app" /Applications/RunGuard.app
/usr/bin/xattr -dr com.apple.quarantine /Applications/RunGuard.app 2>/dev/null || true

echo "Installing helper (asks for your password once)..."
/bin/bash /Applications/RunGuard.app/Contents/Resources/install-helper.sh /Applications/RunGuard.app
open /Applications/RunGuard.app
echo "RunGuard installed in /Applications"
