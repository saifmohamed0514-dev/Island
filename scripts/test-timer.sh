#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-timer-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Timer.swift" <<'PY'
from pathlib import Path
import sys
s=Path('IslandCore/components/Notch/IslandFocus.swift').read_text()
a=s.index('struct IslandTimerState:');b=s.index('@MainActor final class IslandFocusTimer',a)
models=s[a:b]
m=Path('Island/Modules.swift').read_text()
helpers=m[m.index('enum IslandPresetRules'):m.index('extension NotchViews')]
prefs=m[m.index('struct IslandModulePreferences:'):m.index('@MainActor final class IslandModuleStore')]
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
w=Path('Island/DevicesAndWindows.swift').read_text();w=w[w.index('enum IslandWindowLayout:'):w.index('struct IslandWindowSnapView:')]
c=Path('Island/IslandShell.swift').read_text();c=c[c.index('enum IslandCompactKind'):c.index('struct IslandSurface:')]
d=Path('Island/Dashboard.swift').read_text();d=d[d.index('enum IslandWidget:'):d.index('@MainActor final class IslandProfileSchedule')]
Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n'+e+helpers+prefs+models+w+c+d)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Timer.swift" Tests/TimerSmoke.swift Tests/ModuleSmoke.swift -o "$STAGE/test"
"$STAGE/test"
