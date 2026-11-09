#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-media-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Media.swift" <<'PY'
from pathlib import Path
import sys
s=Path('IslandCore/observers/MediaKeyInterceptor.swift').read_text()
e=s[s.index('    private enum NXKeyType:'):s.index('    private var starting')].replace('private enum','enum')
a=s.index('    func start(');b=s.index('    private func handleOptionAction(',a)
main=s[a:b]
h=Path('IslandControls/IslandControls.swift').read_text();h=h[h.index('final class IslandMediaKeyTap {'):]
# Replace only native tap installation; permission guards, heartbeat expiry,
# event filtering, suspension and stop are production code. No global hook is installed.
a=h.index('        let mask=');b=h.index('    func stop()',a)
h=h[:a]+'        fixtureTapStarts+=1;return true\n    }\n'+h[b:]
h=h.replace('private var','var').replace('private func handle','func handle').replace('final class IslandMediaKeyTap {','final class IslandMediaKeyTap {\n    var fixtureTapStarts=0')
fixture='''import Foundation
import AppKit
import ApplicationServices
enum Defaults { enum Key { case hudReplacement };static var enabled=false;static subscript(_ key:Key)->Bool { enabled } }
@MainActor final class XPCHelperClient {
 static let shared=XPCHelperClient()
 var allowed=false,starts=0,stops=0,startResult=true
 var hold=false
 var continuation:CheckedContinuation<Bool,Never>?
 func isAccessibilityAuthorized() async -> Bool { allowed }
 func startMediaKeys() async -> Bool { starts+=1;if hold { return await withCheckedContinuation { continuation=$0 } };return startResult }
 func stopMediaKeys() { stops+=1 }
}
@MainActor final class MediaFixture {
 var mediaActivity:NSObjectProtocol?
 var heartbeat:Task<Void,Never>?
 var heartbeatID:UUID?
 var starting=false,generation=0,running=false
 var keys:[Int]=[]
 var optionCalls=0
 var consumesOption=false
 func handleOptionAction(for key:NXKeyType,command:Bool)->Bool { optionCalls+=1;return consumesOption }
 func handleKeyPress(keyType:NXKeyType,option:Bool,shift:Bool,command:Bool) { keys.append(keyType.rawValue) }
'''
Path(sys.argv[1]).write_text(fixture+e+main+'}\n'+h)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Media.swift" Tests/MediaKeysSmoke.swift -o "$STAGE/test"
"$STAGE/test"
