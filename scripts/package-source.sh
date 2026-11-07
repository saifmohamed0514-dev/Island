#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUTPUT="${1:-$ROOT/dist/Island-Open-Source-Preview.zip}"
if [[ "$OUTPUT" != /* ]]; then OUTPUT="$ROOT/$OUTPUT"; fi
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Commit or set aside source changes before packaging the matching source release.\n' >&2
  exit 1
fi
test -f dist/Island.zip
STAGE="$(mktemp -d /private/tmp/island-complete.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Island-Open-Source"
mkdir -p "$BUNDLE" "$(dirname "$OUTPUT")"
ditto -x -k dist/Island.zip "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE/Island.app"
python3 - "$BUNDLE/Island.app" <<'PY'
import pathlib,plistlib,re,sys
app=pathlib.Path(sys.argv[1]);info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
project=pathlib.Path('Island.xcodeproj/project.pbxproj').read_text()
assert set(re.findall(r'MARKETING_VERSION = ([^;]+);',project)) == {info['CFBundleShortVersionString']},'App/source versions differ'
assert set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);',project)) == {info['CFBundleVersion']},'App/source build numbers differ'
assert info['CFBundleIdentifier']=='org.islandapp.Island'
assert any(item.get('UTTypeIdentifier')=='org.islandapp.module' and 'public.data' in item.get('UTTypeConformsTo',[]) for item in info.get('UTExportedTypeDeclarations',[])),'Missing module drag type'
assert sorted(p.name for p in (app/'Contents/XPCServices').iterdir())==['IslandControls.xpc'],'Unexpected embedded helper'
assert not (app/'Contents/Resources/boring.m4a').exists(),'Obsolete welcome audio'
assert (app/'Contents/Resources/IslandPower').is_file(),'Missing power daemon'
assert (app/'Contents/Library/LoginItems/IslandPowerSetup.app').is_dir(),'Missing setup app'
assert 'SUFeedURL' not in info or info.get('SUPublicEDKey'),'Incomplete update configuration'
PY
git clone --quiet --local --no-hardlinks "$ROOT" "$BUNDLE/Source"
git -C "$BUNDLE/Source" remote remove origin
for DOCUMENT in App-Read-Me.txt FEATURE-STATUS.md VERIFICATION.md START-HERE.md LICENSE THIRD_PARTY_LICENSES UPSTREAM.md; do
  cp "$DOCUMENT" "$BUNDLE/$DOCUMENT"
done
printf '%s\n' "$(git rev-parse HEAD)" > "$BUNDLE/SOURCE-COMMIT.txt"
ditto --norsrc --noextattr -c -k --keepParent "$BUNDLE" "$OUTPUT"
shasum -a 256 "$OUTPUT" > "${OUTPUT%.zip}.sha256"
printf 'Created %s\n' "$OUTPUT"
