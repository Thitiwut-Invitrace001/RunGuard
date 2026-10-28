#!/bin/bash
set -euo pipefail

app_path="${1:?Usage: install-helper.sh /Applications/RunGuard.app}"
if [[ "$EUID" -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$app_path"
fi

helper_source="$app_path/Contents/Library/PrivilegedHelperTools/com.runguard.helper"
helper_target="/Library/PrivilegedHelperTools/com.runguard.helper"
plist="/Library/LaunchDaemons/com.runguard.helper.plist"
label="com.runguard.helper"
console_user=$(/usr/bin/stat -f%Su /dev/console)
[[ -x "$helper_source" && "$console_user" != "root" ]] || { echo "RunGuard.app or logged-in user not found" >&2; exit 1; }
uid=$(/usr/bin/id -u "$console_user")

/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 755 "$helper_source" "$helper_target"

/usr/bin/python3 - "$uid" "$helper_target" "$plist" <<'PY'
import plistlib, sys

uid, helper, plist = sys.argv[1:]
configuration = {
    "Label": "com.runguard.helper",
    "ProgramArguments": [helper, uid],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Background",
}
with open(plist, "wb") as file:
    plistlib.dump(configuration, file)
PY

/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"
/bin/launchctl bootout system "$plist" >/dev/null 2>&1 || true
/bin/launchctl enable "system/$label"
/bin/launchctl bootstrap system "$plist"
/bin/launchctl kickstart -k "system/$label"

for _ in {1..10}; do
  [[ -S /var/run/com.runguard.closedlid.sock ]] && { echo "RunGuard helper installed"; exit 0; }
  /bin/sleep 1
done
echo "RunGuard helper did not start; check: launchctl print system/$label" >&2
exit 1
