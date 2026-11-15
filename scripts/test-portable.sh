#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-portable.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('struct IslandModulePreferences:'):m.index('@MainActor final class IslandModuleStore')]
c=Path('Island/CanvasLayout.swift').read_text();c=c[:c.index('@MainActor final class IslandCanvasStore')]
t=Path('Island/Trays.swift').read_text();t=t[t.index('enum IslandActivityTray:'):t.index('extension UTType')]+t[t.index('struct IslandActivityTrayPreferences:'):t.index('@MainActor final class IslandActivityTrayStore')]
k=Path('Island/IslandShell.swift').read_text();k=k[k.index('enum IslandCompactKind'):k.index('struct IslandSurface:')]
a=Path('Island/Appearance.swift').read_text();a=a[a.index('struct IslandAppearancePreferences:'):a.index('@MainActor final class')]
p=Path('Island/PortableSettings.swift').read_text();p=p[p.index('struct IslandPortableSettings:'):p.index('@MainActor extension')]
v=Path('Island/Visibility.swift').read_text();v=v[v.index('struct IslandVisibilityRules'):v.index('@MainActor final class')]
w=Path('Island/AudioWaveform.swift').read_text();w=w[w.index('enum IslandWaveformRules'):w.index('private final class')]
sounds=Path('Island/SystemSounds.swift').read_text();sounds=sounds[sounds.index('enum IslandSystemSoundEvent'):sounds.index('@MainActor final class')]
bd=Path('Island/BetterDisplay.swift').read_text();bd=bd[bd.index('struct IslandBetterDisplayRequest:'):bd.index('@MainActor final class')]
cap=Path('Island/PlayerCapabilities.swift').read_text()
Path(sys.argv[1]).write_text('import Foundation\nimport SwiftUI\n'+e+m+k+t+c+a+p+v+w+sounds+bd+cap)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/PortableSmoke.swift -o "$STAGE/test"
"$STAGE/test"
