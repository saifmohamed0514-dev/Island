#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-guidance.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('extension NotchViews'):m.index('struct IslandModulePreferences:')]
g=Path('Island/Guidance.swift').read_text();g=g[g.index('struct IslandGuideTopic:'):g.index('struct IslandGuideContent:')]
s=Path('Island/IslandSettings.swift').read_text();s=s[s.index('struct IslandSettingsPage:'):s.index('struct IslandSettingsView:')]
d=Path('Island/ModulePreview.swift').read_text();d=d[d.index('enum IslandModuleGuide'):]
Path(sys.argv[1]).write_text('import Foundation\n'+e+m+d+g+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/GuidanceSmoke.swift -o "$STAGE/check"
"$STAGE/check"
