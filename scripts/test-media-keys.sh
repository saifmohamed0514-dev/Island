#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-media-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Media.swift" <<'PY'
from pathlib import Path
import sys
s=Path('IslandCore/observers/MediaKeyInterceptor.swift').read_text()
e=s[s.index('    private enum NXKeyType:'):s.index('    private var suspendedByUser')].replace('private enum','enum')
a=s.index('    private func handleEvent(');b=s.index('    private func handleOptionAction(',a)
handler=s[a:b].replace('private func handleEvent','func handleEvent')
fixture='''import Foundation
import AppKit
import ApplicationServices
enum Defaults { enum Key { case hudReplacement };static subscript(_ key:Key)->Bool { false } }
@MainActor final class MediaFixture {
 var suspendedByUser=false
 var eventTap:CFMachPort?
 var keys:[Int]=[]
 var optionCalls=0
 var consumesOption=false
 func handleOptionAction(for key:NXKeyType,command:Bool)->Bool { optionCalls+=1;return consumesOption }
 func handleKeyPress(keyType:NXKeyType,option:Bool,shift:Bool,command:Bool) { keys.append(keyType.rawValue) }
'''
Path(sys.argv[1]).write_text(fixture+e+handler+'}\n')
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Media.swift" Tests/MediaKeysSmoke.swift -o "$STAGE/test"
"$STAGE/test"
