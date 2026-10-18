#!/bin/sh
# Writes the launchd plist SMAppService registers Native's host with, from LaunchAgent.plist.
# Each channel (Native, Native Nightly, each Debug build folder) gets a host of its own
# (docs/durability.md, "Development builds").
set -eu
# Native Nightly sets NATIVE_HOST_CHANNEL=nightly (Config/Nightly.xcconfig), so it never shares a
# host with Native. Debug builds get a channel per build folder and run as development hosts.
channel="${NATIVE_HOST_CHANNEL:-}"
development=""
if [ "$CONFIGURATION" = "Debug" ]; then
    channel=$(printf '%s' "$BUILT_PRODUCTS_DIR" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-10)
    development=1
fi
label="$PRODUCT_BUNDLE_IDENTIFIER.host"
[ -n "$channel" ] && label="$label.$channel"
mkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_0")"
/usr/bin/sed -e "s|__LABEL__|$label|g" -e "s|__APP_ID__|$PRODUCT_BUNDLE_IDENTIFIER|g" -e "s|__CHANNEL__|$channel|g" \
    -e "s|__DEVELOPMENT__|$development|g" \
    "$SCRIPT_INPUT_FILE_0" > "$SCRIPT_OUTPUT_FILE_0"
