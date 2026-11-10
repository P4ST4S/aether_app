#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project Aether.xcodeproj -scheme Aether -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
