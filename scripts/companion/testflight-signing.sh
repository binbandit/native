#!/usr/bin/env bash
# App Store signing lives in a throwaway keychain; Developer ID signing cannot sign an iOS app.
set -euo pipefail
work=${RUNNER_TEMP:?}/native-testflight-signing
keychain="$work/distribution.keychain-db"

case ${1:-} in
    setup)
        for name in IOS_DISTRIBUTION_P12 IOS_DISTRIBUTION_PASSWORD IOS_PROVISIONING_PROFILE NATIVE_TEAM_ID; do
            [ -n "${!name:-}" ] || { echo "error: missing $name (docs/releasing.md, TestFlight)" >&2; exit 1; }
        done
        umask 077
        mkdir -p "$work"
        security list-keychains -d user > "$work/keychains.txt"
        password=$(uuidgen)
        security create-keychain -p "$password" "$keychain"
        security set-keychain-settings -lut 21600 "$keychain"
        security unlock-keychain -p "$password" "$keychain"
        # Preserve each existing path, including spaces, for both setup and teardown.
        keychains=()
        while IFS= read -r line; do
            line=${line#*\"}; line=${line%\"*}
            [ -z "$line" ] || keychains+=("$line")
        done < "$work/keychains.txt"
        security list-keychains -d user -s "$keychain" "${keychains[@]}"
        printf '%s' "$IOS_DISTRIBUTION_P12" | base64 --decode > "$work/certificate.p12"
        security import "$work/certificate.p12" -k "$keychain" -P "$IOS_DISTRIBUTION_PASSWORD" \
            -T /usr/bin/codesign -T /usr/bin/security
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
        rm "$work/certificate.p12"
        printf '%s' "$IOS_PROVISIONING_PROFILE" | base64 --decode > "$work/profile.mobileprovision"
        security cms -D -i "$work/profile.mobileprovision" > "$work/profile.plist"
        python3 - "$work" <<'PY'
import datetime
import os
from pathlib import Path
import plistlib
import sys

work = Path(sys.argv[1])
profile = plistlib.loads((work / "profile.plist").read_bytes())
team = os.environ["NATIVE_TEAM_ID"]
bundle = "dev.binbandit.native.companion"
entitlements = profile["Entitlements"]
if (profile["TeamIdentifier"] != [team]
        or entitlements["application-identifier"] != f"{team}.{bundle}"
        or entitlements.get("get-task-allow", False)
        or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices", False)
        or not entitlements.get("beta-reports-active", False)
        or profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)):
    raise SystemExit("error: expected an unexpired App Store profile for Native's team and companion bundle ID")
uuid = profile["UUID"]
# The UUID comes from a signed Apple profile; validate before using it in a path or GitHub output.
import uuid as uuid_module
uuid_module.UUID(uuid)
folder = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
folder.mkdir(parents=True, exist_ok=True)
destination = folder / f"{uuid}.mobileprovision"
# Preserve a pre-existing runner profile rather than deleting it during cleanup.
if destination.exists():
    (work / "previous.mobileprovision").write_bytes(destination.read_bytes())
destination.write_bytes((work / "profile.mobileprovision").read_bytes())
(work / "installed-profile.txt").write_text(str(destination))
export = {"method": "app-store-connect", "signingStyle": "manual", "teamID": team,
          "signingCertificate": "Apple Distribution", "manageAppVersionAndBuildNumber": False,
          "provisioningProfiles": {bundle: uuid}, "uploadSymbols": True}
(work / "ExportOptions.plist").write_bytes(plistlib.dumps(export))
with open(os.environ["GITHUB_ENV"], "a") as output:
    output.write(f"IOS_PROFILE_UUID={uuid}\nIOS_SIGNING_KEYCHAIN={work / 'distribution.keychain-db'}\n")
    output.write(f"IOS_EXPORT_OPTIONS={work / 'ExportOptions.plist'}\n")
PY
        ;;
    teardown)
        if [ -f "$work/installed-profile.txt" ]; then
            profile=$(cat "$work/installed-profile.txt")
            if [ -f "$work/previous.mobileprovision" ]; then
                cp "$work/previous.mobileprovision" "$profile"
            else
                rm -f "$profile"
            fi
        fi
        if [ -f "$work/keychains.txt" ]; then
            keychains=()
            while IFS= read -r line; do
                line=${line#*\"}; line=${line%\"*}
                [ -z "$line" ] || keychains+=("$line")
            done < "$work/keychains.txt"
            security list-keychains -d user -s "${keychains[@]}"
        fi
        security delete-keychain "$keychain" 2>/dev/null || true
        rm -rf "$work"
        ;;
    *) echo "usage: $0 setup|teardown" >&2; exit 1 ;;
esac
