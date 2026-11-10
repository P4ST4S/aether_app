#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d /Applications/Aether.app ]]; then
  ./Scripts/build.sh
fi
open -g /Applications/Aether.app
