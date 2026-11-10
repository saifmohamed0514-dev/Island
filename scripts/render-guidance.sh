#!/bin/bash
# Render actual guidance and saved-layout views using isolated sample state.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:?Pass an output directory}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d /private/tmp/island-guidance-render.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Views.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('extension NotchViews'):m.index('@MainActor final class IslandModuleStore')]
g=Path('Island/Guidance.swift').read_text()
s=Path('Island/IslandSettings.swift').read_text();s=s[s.index('struct IslandSettingsPage:'):s.index('struct IslandSettingsView:')]
d=Path('Island/ModulePreview.swift').read_text();d=d[d.index('enum IslandModuleGuide'):]
c=Path('Island/CanvasLayout.swift').read_text();c=c[c.index('struct IslandCanvasPreferences:'):c.index('@MainActor final class IslandCanvasStore')]
l=Path('Island/SavedLayouts.swift').read_text().replace('static let shared=IslandSavedLayoutStore()','static let shared=IslandSavedLayoutStore(defaults:UserDefaults(suiteName:"IslandGuidanceRender.Fixture")!)')
h='enum IslandHaptics { enum Event { case confirmation };static func play(_ event:Event) {} }\n'
Path(sys.argv[1]).write_text('import SwiftUI\nimport Combine\nimport Foundation\n'+e+m+d+c+s+h+g+l)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/GuidanceRender.swift -o "$STAGE/render"
"$STAGE/render" "$OUTPUT"
