#!/bin/bash
# Runs the pure-logic tests. Wrapper exists because `swift test` alone does NOT work here:
# Klip builds on the Command Line Tools (no Xcode), and CLT ships swift-testing in a layout
# SwiftPM doesn't search — Testing.framework in Library/Developer/Frameworks and its
# lib_TestingInterop.dylib one level over in Library/Developer/usr/lib. So: -F to compile
# against the framework, plus an rpath for each so dyld can load them at run time.
# With Xcode installed, plain `swift test` works and this wrapper is harmless.
set -euo pipefail
cd "$(dirname "$0")"

CLT="$(xcode-select -p)"
FW="$CLT/Library/Developer/Frameworks"
LIB="$CLT/Library/Developer/usr/lib"

if [ ! -d "$FW/Testing.framework" ]; then
    echo "==> Testing.framework not found under $FW — running plain 'swift test'."
    exec swift test "$@"
fi

exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
