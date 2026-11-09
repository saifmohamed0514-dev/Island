#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-media-xpc.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
stage=Path(sys.argv[1]);client=Path('IslandCore/XPCHelperClient/IslandControlsProtocol.swift').read_text();server=Path('IslandControls/IslandControlsProtocol.swift').read_text()
signatures=lambda s:[line.strip() for line in s.splitlines() if line.strip().startswith(('func ','@objc protocol'))]
assert signatures(client)==signatures(server),'Client/server XPC interfaces differ'
(stage/'Protocol.swift').write_text(server)
s=Path('IslandControls/IslandControls.swift').read_text()
a=s.index('    private func accessibilityAllowed()');b=s.index('    // Hold the actual clicked window',a)
s=s[:a]+'    private func accessibilityAllowed()->Bool { true }\n'+s[b:]
a=s.index('        let mask=',s.index('final class IslandMediaKeyTap'));b=s.index('    func stop()',a)
s=s[:a]+'        return true\n    }\n'+s[b:]
s=s.replace('private let mediaTap=','let mediaTap=').replace('private var send:','var send:').replace('private func handle(type:','func handle(type:')
(stage/'Server.swift').write_text(s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Protocol.swift" "$STAGE/Server.swift" Tests/MediaXPCSmoke.swift -o "$STAGE/test"
"$STAGE/test"
