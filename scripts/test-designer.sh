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
t=Path('Island/ModulePreview.swift').read_text();t=t[t.index('extension UTType'):t.index('// Sample content only:')]
Path(sys.argv[1]).write_text('import Foundation\nimport CoreTransferable\nimport UniformTypeIdentifiers\n'+e+m+t)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/DesignerSmoke.swift -o "$STAGE/test"
"$STAGE/test"
