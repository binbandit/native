#!/bin/sh
# Writes the launchd plist SMAppService registers Native's host with, from LaunchAgent.plist.
# Debug builds get a channel of their own, derived from the build folder, so builds from different
# DerivedData folders never share a host (docs/durability.md, "Development builds").
set -eu
label="$PRODUCT_BUNDLE_IDENTIFIER.host"
channel=""
if [ "$CONFIGURATION" = "Debug" ]; then
    channel=$(printf '%s' "$BUILT_PRODUCTS_DIR" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-10)
    label="$label.$channel"
fi
mkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_0")"
/usr/bin/sed -e "s|__LABEL__|$label|g" -e "s|__APP_ID__|$PRODUCT_BUNDLE_IDENTIFIER|g" -e "s|__CHANNEL__|$channel|g" \
    "$SCRIPT_INPUT_FILE_0" > "$SCRIPT_OUTPUT_FILE_0"
