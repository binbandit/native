#!/bin/bash
# Removes the architectures a build doesn't target from the executables of the frameworks Xcode
# embeds, which its script phase passes as input files after this script. Sparkle ships universal,
# but Native runs only on Apple silicon (macOS 27 has no Intel Macs), so its x86_64 slices are
# about 1.2 MB nobody runs (docs/app-size.md). lipo keeps each remaining slice's own code signature,
# so the helpers stay signed as Sparkle ships them, the framework still verifies, and Xcode signs
# the app around it as before.
set -euo pipefail

for index in $(seq 1 $((SCRIPT_INPUT_FILE_COUNT - 1))); do
    input="SCRIPT_INPUT_FILE_$index"
    binary=${!input}
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
    mkdir -p "$DERIVED_FILE_DIR"
    thinned="$DERIVED_FILE_DIR/thin-$index"
    if [ "$kept" = 1 ]; then
        lipo "$binary" -thin "${extract[1]}" -output "$thinned"
    else
        lipo "$binary" "${extract[@]}" -output "$thinned"
    fi
    # Writes over the binary in place, keeping its permissions.
    cat "$thinned" >"$binary"
    rm -f "$thinned"
done
touch "$SCRIPT_OUTPUT_FILE_0"
