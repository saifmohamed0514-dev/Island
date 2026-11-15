#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-appearance.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Island/Appearance.swift').read_text();s=s[:s.index('struct IslandAppearanceSettings:')]
h=Path('Island/HUDCustomization.swift').read_text();h=h[h.index('enum IslandHUDRules'):h.index('@MainActor enum IslandHUDMotion')]
g=Path('Island/ActivityInteractions.swift').read_text();g=g[g.index('struct IslandSwipeAccumulator'):g.index('// Monitors only')]
l=Path('Island/LockWidgets.swift').read_text();l=l[:l.index('@MainActor final class IslandLockScreenController')]
Path(sys.argv[1]).write_text(s+h+g+l)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/AppearanceSmoke.swift -o "$STAGE/test"
"$STAGE/test"
