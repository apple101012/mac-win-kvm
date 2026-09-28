#!/usr/bin/env bash
# Run the Swift unit tests with the Command Line Tools (no Xcode licence needed).
set -euo pipefail
cd "$(dirname "$0")"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
