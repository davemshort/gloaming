#!/bin/zsh
# Runs the unit tests reliably with the Command Line Tools alone (no Xcode).
#
# Why not plain `swift test`: with Swift 6.4 and the Command Line Tools, the default
# "swiftbuild" build system intermittently fails with "plugin for module 'TestingMacros'
# not found", and then keeps failing, even after `swift package clean`. The classic
# ("native") build system works, but only when given the Swift Testing framework and
# macro-plugin paths explicitly. With full Xcode installed, plain `swift test` should work.
set -euo pipefail
cd "${0:A:h}/.."

DEV="$(xcode-select -p)"
if [[ "$DEV" == *CommandLineTools* ]]; then
    FW="$DEV/Library/Developer/Frameworks"
    PLUGINS="$DEV/usr/lib/swift/host/plugins/testing"
    exec swift test --build-system native \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xswiftc -plugin-path -Xswiftc "$PLUGINS" \
        -Xlinker -rpath -Xlinker "$FW" \
        "$@"
else
    exec swift test "$@"
fi
