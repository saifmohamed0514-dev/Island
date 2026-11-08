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
scripts/test-transition.sh
scripts/test-permissions.sh
scripts/test-media-keys.sh
scripts/test-designer.sh
scripts/test-files.sh
scripts/test-bridge.sh
scripts/test-advanced.sh
scripts/test-snapping.sh
scripts/test-refinement.sh
scripts/test-services.sh
BUILD_ARGS=()
if [[ -n "${ISLAND_PACKAGES_DIR:-}" ]]; then BUILD_ARGS+=(-clonedSourcePackagesDirPath "$ISLAND_PACKAGES_DIR"); fi
BUILD_ACTIONS=(clean build)
if [[ "${ISLAND_INCREMENTAL:-0}" == 1 ]]; then BUILD_ACTIONS=(build); fi
xcodebuild -project Island.xcodeproj -scheme Island -configuration Release -derivedDataPath "$BUILD" "${BUILD_ARGS[@]}" -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO "${BUILD_ACTIONS[@]}"
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
xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path "$STAGE/cache" Power/IslandPower.swift -o "$STAGE/Island.app/Contents/Resources/IslandPower"
codesign --force --sign - "$STAGE/Island.app/Contents/Resources/IslandPower"
SETUP="$STAGE/Island.app/Contents/Library/LoginItems/IslandPowerSetup.app"
mkdir -p "$SETUP/Contents/MacOS"
xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path "$STAGE/cache" Power/PowerInstaller.swift Power/PowerSetup.swift -o "$SETUP/Contents/MacOS/IslandPowerSetup"
python3 - "$SETUP/Contents/Info.plist" "$STAGE/Island.app/Contents/Info.plist" <<'SETUPINFO'
import plistlib,sys
from pathlib import Path
parent=plistlib.loads(Path(sys.argv[2]).read_bytes())
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.islandapp.Island.PowerSetup','CFBundleName':'Island Power Setup','CFBundleDisplayName':'Island Power Setup','CFBundleExecutable':'IslandPowerSetup','CFBundlePackageType':'APPL','CFBundleShortVersionString':parent['CFBundleShortVersionString'],'CFBundleVersion':parent['CFBundleVersion'],'LSUIElement':True,'NSHighResolutionCapable':True,'NSAppleEventsUsageDescription':'Approve the one-time Low Power Mode controls you requested in Island.'}))
SETUPINFO
codesign --force --sign - "$SETUP"

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
scripts/test-power-installer.sh "$STAGE/Island.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Island.app" dist/Island.zip
printf '\nCreated dist/Island.zip (local ad-hoc signature; not notarized).\n'
