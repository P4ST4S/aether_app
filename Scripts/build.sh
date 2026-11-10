#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if /usr/bin/pgrep -x Aether >/dev/null; then
  print -u2 'Quit Aether from its menu bar menu before building and installing an update.'
  exit 1
fi
if [[ ! -w /Applications ]]; then
  print -u2 'Applications is not writable. Run the build from an account allowed to install applications.'
  exit 1
fi

xcodebuild -project Aether.xcodeproj -scheme Aether -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build CODE_SIGN_IDENTITY=- build

# Stage and verify the complete bundle before replacing the installed version.
staging=$(/usr/bin/mktemp -d /Applications/.aether-install.XXXXXX)
trap '/bin/rm -rf -- "$staging"' EXIT
/usr/bin/ditto .build/Build/Products/Release/Aether.app "$staging/Aether.app"
/usr/bin/codesign --verify --deep --strict "$staging/Aether.app"
if [[ -e /Applications/Aether.app ]]; then
  /bin/mv /Applications/Aether.app "$staging/Previous.app"
fi
if ! /bin/mv "$staging/Aether.app" /Applications/Aether.app; then
  if [[ -d "$staging/Previous.app" ]]; then
    /bin/mv "$staging/Previous.app" /Applications/Aether.app
  fi
  exit 1
fi
print '\nInstalled: /Applications/Aether.app'
print 'Open Aether from Applications, or run ./Scripts/run.sh. It stays in the menu bar until invoked.'
