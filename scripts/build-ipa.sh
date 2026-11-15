#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build-native.sh appletvos
xcodegen generate
xcodebuild -resolvePackageDependencies -project Watchly.xcodeproj -scheme Watchly
xcodebuild -project Watchly.xcodeproj -scheme Watchly -configuration Release \
  -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build
APP="$ROOT/build/DerivedData/Build/Products/Release-appletvos/Watchly.app"
test -f "$APP/Watchly"
python3 scripts/package-ipa.py "$APP" "$ROOT/build/Watchly-tvOS-unsigned.ipa"
echo 'Unsigned tvOS IPA ready. Sign and install it with atvloadly.'
