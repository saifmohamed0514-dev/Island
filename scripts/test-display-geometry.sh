#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-display.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
s=Path('IslandCore/sizing/matters.swift').read_text();s=s[s.index('struct IslandDisplayMetrics:'):s.index('@MainActor func getScreenFrame')]
v=Path('IslandCore/models/IslandViewModel.swift').read_text();v=v[v.index('    func refreshClosedGeometry()'):v.index('    // Computed property for effective notch height')]
fixture='''
enum State { case closed,open }
@MainActor var fixtureSize=CGSize(width:185,height:33.5)
@MainActor func getClosedNotchSize(screenUUID:String?)->CGSize { fixtureSize }
@MainActor final class GeometryModel {
 var screenUUID:String?;var notchState=State.closed
 var notchSize=CGSize(width:185,height:32),closedNotchSize=CGSize(width:185,height:32)
'''+v+'}\n'
Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n'+s+fixture)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/DisplayGeometrySmoke.swift -o "$STAGE/test"
"$STAGE/test"
