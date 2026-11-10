#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-designer-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('struct IslandModulePreferences:'):m.index('@MainActor final class IslandModuleStore')]
t=Path('Island/ModulePreview.swift').read_text();t=t[t.index('extension UTType'):t.index('// These are sample module blocks')]
c=Path('Island/CanvasLayout.swift').read_text();c=c[c.index('struct IslandCanvasPreferences:'):c.index('struct IslandCanvasLiveView:')]
l=Path('Island/SavedLayouts.swift').read_text();l=l[l.index('struct IslandSavedLayout:'):l.index('struct IslandSavedLayoutsView:')]
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\nimport CoreTransferable\nimport UniformTypeIdentifiers\n'+e+m+t+c+l)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/DesignerSmoke.swift Tests/CanvasSmoke.swift Tests/SavedLayoutsSmoke.swift -o "$STAGE/test"
"$STAGE/test"
