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
a=s.index('    func start(');b=s.index('    func stop()',a)
startup=s[a:b]
# Replace only creation of the native tap. All authorization/generation guards
# are the real startup code, and the passive-input check is a forbidden boundary.
native=startup.index('        let mask =');startup=startup[:native]+'        fixtureTapStarts+=1\n    }\n'
startup=startup.replace('CGPreflightListenEventAccess()', 'forbiddenPassiveInputCheck()')
a=s.index('    func stop()');b=s.index('    // MARK: - Event Handling',a)
stop=s[a:b]
fixture='''import Foundation
import AppKit
import ApplicationServices
enum Defaults { enum Key { case hudReplacement };static var enabled=false;static subscript(_ key:Key)->Bool { enabled } }
enum IslandSystemPermissionClient { static var allowed=false;static func mainAccessibilityAuthorized()->Bool { allowed } }
@MainActor final class MediaFixture {
 var suspendedByUser=false
 var starting=false
 var generation=0
 var runLoopSource:CFRunLoopSource?
 var fixtureTapStarts=0
 var passiveInputChecks=0
 func forbiddenPassiveInputCheck()->Bool { passiveInputChecks+=1;return false }
 func ensureAccessibilityAuthorization(promptIfNeeded:Bool) async -> Bool { IslandSystemPermissionClient.allowed }
 var eventTap:CFMachPort?
 var keys:[Int]=[]
 var optionCalls=0
 var consumesOption=false
 func handleOptionAction(for key:NXKeyType,command:Bool)->Bool { optionCalls+=1;return consumesOption }
 func handleKeyPress(keyType:NXKeyType,option:Bool,shift:Bool,command:Bool) { keys.append(keyType.rawValue) }
'''
Path(sys.argv[1]).write_text(fixture+e+startup+stop+handler+'}\n')
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Media.swift" Tests/MediaKeysSmoke.swift -o "$STAGE/test"
"$STAGE/test"
