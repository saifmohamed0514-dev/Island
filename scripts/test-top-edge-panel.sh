#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-edge-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Geometry.swift" <<'PY'
from pathlib import Path
import sys
s=Path('IslandCore/sizing/matters.swift').read_text()
s=s[s.index('struct IslandDisplayMetrics:'):s.index('@MainActor func getScreenFrame')]
Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n'+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Geometry.swift" Island/TopEdgePanel.swift Tests/TopEdgePanelSmoke.swift -o "$STAGE/check"
"$STAGE/check"
