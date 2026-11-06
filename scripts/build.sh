#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="${ISLAND_BUILD_DIR:-$ROOT/.build}"
STAGE="$(mktemp -d /private/tmp/island-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 -m unittest discover -s Tests -p 'test_*.py'
scripts/test-timer.sh
scripts/test-completion.sh
scripts/test-files.sh
scripts/test-bridge.sh
BUILD_ARGS=()
if [[ -n "${ISLAND_PACKAGES_DIR:-}" ]]; then BUILD_ARGS+=(-clonedSourcePackagesDirPath "$ISLAND_PACKAGES_DIR"); fi
xcodebuild -project Island.xcodeproj -scheme Island -configuration Release -derivedDataPath "$BUILD" "${BUILD_ARGS[@]}" -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO clean build
for PACKAGE_ROOT in "$BUILD/SourcePackages" "${ISLAND_PACKAGES_DIR:-$BUILD/SourcePackages}"; do
  if [[ -d "$PACKAGE_ROOT/artifacts" ]]; then
    SIGN_TOOL="$(find "$PACKAGE_ROOT/artifacts" -type f -name sign_update -print -quit)"
    if [[ -n "$SIGN_TOOL" ]]; then
      ISLAND_SPARKLE_SIGN_TOOL="$SIGN_TOOL" python3 -m unittest discover -s Tests -p 'test_*.py'
      break
    fi
  fi
done
mkdir -p dist
ditto --norsrc --noextattr "$BUILD/Build/Products/Release/Island.app" "$STAGE/Island.app"
cp Assets/Island.icns "$STAGE/Island.app/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path "$STAGE/cache" Integrations/IslandBridge.swift -o "$STAGE/Island.app/Contents/Resources/IslandBridge"
codesign --force --sign - "$STAGE/Island.app/Contents/Resources/IslandBridge"
xattr -cr "$STAGE/Island.app"
codesign --force --deep --sign - "$STAGE/Island.app"
codesign --force --sign - --entitlements IslandControls/IslandControls.entitlements "$STAGE/Island.app/Contents/XPCServices/IslandControls.xpc"
python3 - "$STAGE/entitlements.plist" <<'PY'
import plistlib,sys
from pathlib import Path
d=Path('IslandCore/Island.entitlements').read_text().replace('$(PRODUCT_BUNDLE_IDENTIFIER)', 'org.islandapp.Island')
Path(sys.argv[1]).write_text(d)
PY
codesign --force --sign - --entitlements "$STAGE/entitlements.plist" "$STAGE/Island.app"
codesign --verify --deep --strict "$STAGE/Island.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Island.app" dist/Island.zip
printf '\nCreated dist/Island.zip (local ad-hoc signature; not notarized).\n'
