#!/bin/bash
# Offscreen SwiftUI layout renders of the actual editor/preview source, with
# isolated in-memory module fixtures and sample defaults. No window or OS access.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:?Pass an output directory}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d /private/tmp/island-designer-render.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Views.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('extension NotchViews'):m.index('@MainActor final class IslandModuleStore')]
s=Path('Island/IslandShell.swift').read_text();s=s[s.index('struct IslandSurface:'):s.index('struct IslandMark:')]
p=Path('Island/ModulePreview.swift').read_text()
d=Path('Island/ModuleDesigner.swift').read_text();d=d[d.index('struct IslandModuleDesigner:'):d.index('struct IslandModuleInspector:')]
fixture='''
@MainActor final class IslandModuleStore:ObservableObject {
 static let shared=IslandModuleStore()
 @Published var preferences:IslandModulePreferences
 var enabled:[NotchViews] { preferences.enabled }
 var defaultModule:NotchViews { preferences.start }
 init() { var p=IslandModulePreferences();p.enabled=[.dashboard,.home,.shelf,.focus,.notes,.weather,.agents];p.normalize();preferences=p }
 func place(_ module:NotchViews,relativeTo target:NotchViews?=nil,after:Bool=false)->Bool { preferences.place(module,relativeTo:target,after:after);return true }
 func restore(_ value:IslandModulePreferences) { preferences=value }
 func setDefault(_ value:NotchViews) { preferences.start=value }
 func setEnabled(_ value:NotchViews,_ enabled:Bool) { }
 func profile(_ name:String) { }
}
struct IslandModuleInspector:View { let module:NotchViews;var body:some View { Text(module.title) } }
'''
Path(sys.argv[1]).write_text('import SwiftUI\nimport Combine\nimport Foundation\n'+e+m+s+p+fixture+d)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/DesignerRender.swift -o "$STAGE/render"
"$STAGE/render" "$OUTPUT"
