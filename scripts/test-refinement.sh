#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-refinement.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Rules.swift" <<'PY'
from pathlib import Path
import sys
u=Path('Island/Updates.swift').read_text();u=u[u.index('enum IslandUpdateRules'):u.index('@MainActor final class')]
h=Path('Island/Haptics.swift').read_text();h=h[h.index('enum IslandHapticEvent'):h.index('@MainActor enum')]
c=Path('Island/IslandShell.swift').read_text();c=c[c.index('enum IslandCompactKind'):c.index('struct IslandSurface:')]
a=Path('Island/LiveActivities.swift').read_text();a=a[a.index('enum IslandActivityRules'):a.index('@MainActor final class')]
s=Path('Island/IslandSettings.swift').read_text();s=s[s.index('struct IslandSettingsPage:'):s.index('struct IslandSettingsView:')]
Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n'+u+h+c+a+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Rules.swift" Tests/RefinementSmoke.swift -o "$STAGE/check"
"$STAGE/check"
