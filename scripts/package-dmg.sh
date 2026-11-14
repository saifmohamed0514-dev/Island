#!/bin/bash
# Package the reviewed app and its matching source; never publish or change the app.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Commit the matching source before creating a release DMG.\n' >&2
  exit 1
fi
STAGE="$(mktemp -d /private/tmp/island-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Installer"
ditto -x -k dist/Island.zip "$STAGE/Installer"
APP="$STAGE/Installer/Island.app"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUTPUT="${1:-$ROOT/dist/Island-$VERSION.dmg}"
if [[ "$OUTPUT" != /* ]]; then OUTPUT="$ROOT/$OUTPUT"; fi
if [[ -e "$OUTPUT" ]]; then
  printf 'The output already exists. Move it aside or choose a new output path.\n' >&2
  exit 1
fi
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib,re,sys
info=plistlib.loads((Path(sys.argv[1])/'Contents/Info.plist').read_bytes())
project=Path('Island.xcodeproj/project.pbxproj').read_text()
assert set(re.findall(r'MARKETING_VERSION = ([^;]+);',project))=={info['CFBundleShortVersionString']},'Rebuild first: app/source versions differ'
assert set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);',project))=={info['CFBundleVersion']},'Rebuild first: app/source build numbers differ'
assert info['CFBundleIdentifier']=='org.islandapp.Island'
PY
ln -s /Applications "$STAGE/Installer/Applications"
HELP="$STAGE/Installer/Source and Help"
mkdir -p "$HELP"
git archive --format=zip --prefix=Island-Source/ HEAD > "$HELP/Island-Source.zip"
git rev-parse HEAD > "$HELP/SOURCE-COMMIT.txt"
for DOCUMENT in LICENSE THIRD_PARTY_LICENSES UPSTREAM.md INSTALL.md FEATURE-STATUS.md VERIFICATION.md App-Read-Me.txt; do
  cp "$DOCUMENT" "$HELP/$DOCUMENT"
done
python3 - "$APP" "$STAGE/Installer/Install Island.txt" <<'PY'
from pathlib import Path
import plistlib,sys
info=plistlib.loads((Path(sys.argv[1])/'Contents/Info.plist').read_bytes())
feed=info.get('SUFeedURL')
updates=('This build checks your configured release channel when you enable updates in Island Settings → Updates. Published signed releases are required.\nRelease feed: '+feed) if feed else 'This preview has no release channel connected yet. It cannot receive automatic updates until its owner configures the GitHub repository and rebuilds it.'
Path(sys.argv[2]).write_text(f'''Welcome to Island {info['CFBundleShortVersionString']} (build {info['CFBundleVersion']})

1. Quit an older Island if it is running.
2. Drag Island.app onto the Applications folder beside it.
3. Open Island from Applications, then eject this disk image.
4. Follow the first-start guide. Existing preferences are kept when updating.

Requires an Apple silicon Mac with macOS 15 or newer.
This is a locally signed development preview, not Apple-notarized. macOS may block it after downloading on another Mac.

IF MACOS BLOCKS ISLAND
1. Try opening Island from Applications once, then dismiss the blocked-app message.
2. Open System Settings → Privacy & Security and scroll to Security.
3. Find Island and choose Open Anyway. Some macOS versions show Open first.
4. Approve the Mac’s authentication prompt yourself, then choose Open.

Use this only for a download you trust. Open Anyway usually appears for about an hour after the blocked attempt; try opening Island again if it is missing. A managed Mac may need its administrator. Apple’s instructions: https://support.apple.com/102445

UPDATES
{updates}

OPEN SOURCE
The matching source, GPL license, third-party notices and verification report are in Source and Help. Unzip Island-Source.zip to build or modify the app. No user data, passwords or private signing keys are included.
''')
PY
mkdir -p "$(dirname "$OUTPUT")"
hdiutil create -quiet -volname Island -fs APFS -srcfolder "$STAGE/Installer" -format ULFO "$STAGE/Island.dmg"
hdiutil verify "$STAGE/Island.dmg"
mv "$STAGE/Island.dmg" "$OUTPUT"
python3 - "$OUTPUT" <<'PY'
from pathlib import Path
import hashlib,sys
p=Path(sys.argv[1]);p.with_suffix('.dmg.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
PY
printf 'Created %s\nNo files were published.\n' "$OUTPUT"
