#!/bin/bash
# Removes the architectures a build doesn't target from the helper executables inside the frameworks
# Xcode embeds, which its script phase names as output files. Sparkle ships universal, but app
# builds are arm64 only (docs/releasing.md), so the x86_64 slices of its Autoupdate, Updater,
# Downloader and Installer are about 0.75 MB nobody runs (docs/app-size.md). lipo keeps each
# remaining slice's own code signature, so the helpers stay signed as Sparkle ships them, the
# framework still verifies, and Xcode signs the app around them as before.
#
# The script sandbox lets the phase write only its declared outputs and TEMP_DIR. The framework's
# own binary stays universal: Xcode's embed step already declares it, and a second producer is an
# error.
set -euo pipefail

for index in $(seq 0 $((SCRIPT_OUTPUT_FILE_COUNT - 1))); do
    output="SCRIPT_OUTPUT_FILE_$index"
    binary=${!output}
    # A build without the framework has nothing to thin.
    [ -f "$binary" ] || continue
    present=$(lipo -archs "$binary")
    extract=()
    for arch in $ARCHS; do
        case " $present " in *" $arch "*) extract+=(-extract "$arch") ;; esac
    done
    # Leave the binary as it is when it has nothing else, or nothing this build runs.
    kept=$((${#extract[@]} / 2))
    [ "$kept" -gt 0 ] && [ "$kept" -lt "$(wc -w <<<"$present")" ] || continue
    thinned="$TEMP_DIR/thin-embedded-framework-$index"
    if [ "$kept" = 1 ]; then
        lipo "$binary" -thin "${extract[1]}" -output "$thinned"
    else
        lipo "$binary" "${extract[@]}" -output "$thinned"
    fi
    # Writes over the binary in place, keeping its permissions.
    cat "$thinned" >"$binary"
    rm -f "$thinned"
done
