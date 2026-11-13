#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-trays-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
c=Path('Island/IslandShell.swift').read_text();c=c[c.index('enum IslandCompactKind'):c.index('struct IslandSurface:')]
t=Path('Island/Trays.swift').read_text();t=t[t.index('enum IslandActivityTray:'):t.index('struct IslandTraysSettings:')]
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\nimport CoreGraphics\n'+c+t)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/TraysSmoke.swift -o "$STAGE/check"
"$STAGE/check"
