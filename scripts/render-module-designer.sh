#!/bin/bash
# Offscreen SwiftUI layout renders of the actual editor/preview source, with
# isolated in-memory module fixtures and sample defaults. Default: no window.
# ISLAND_DESIGNER_DEMO=1 builds a separate, explicitly launched fixture window.
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
c=Path('Island/CanvasLayout.swift').read_text();c=c[c.index('struct IslandCanvasPreferences:'):c.index('@MainActor final class IslandCanvasStore')]
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
 func enableForCanvas(_ values:[NotchViews]) { preferences.enabled += values+[.dashboard];preferences.start = .dashboard;preferences.normalize() }
}
@MainActor final class IslandCanvasStore:ObservableObject {
 static let shared=IslandCanvasStore()
 @Published var preferences=IslandCanvasPreferences()
 func place(_ module:NotchViews,at index:Int) { preferences.place(module,at:index) }
 func remove(_ module:NotchViews) { preferences.remove(module) }
 func setEnabled(_ value:Bool) { preferences.enabled=value }
 func template(_ name:String) { }
 func restore(_ value:IslandCanvasPreferences) { preferences=value }
}
struct IslandModuleInspector:View { let module:NotchViews;var body:some View { Text(module.title) } }
'''
Path(sys.argv[1]).write_text('import SwiftUI\nimport Combine\nimport Foundation\n'+e+m+c+s+p+fixture+d)
PY
if [[ "${ISLAND_DESIGNER_DEMO:-0}" == 1 ]]; then
    APP="$OUTPUT/Island Canvas Check.app"
    mkdir -p "$APP/Contents/MacOS"
    xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/DesignerDemo.swift -o "$APP/Contents/MacOS/IslandCanvasCheck"
    python3 - "$APP/Contents/Info.plist" <<'INFO'
import plistlib,sys
from pathlib import Path
types=plistlib.loads(Path('IslandCore/Info.plist').read_bytes())['UTExportedTypeDeclarations']
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.islandapp.CanvasCheck','CFBundleName':'Island Canvas Check','CFBundleDisplayName':'Island Layout Check','CFBundleExecutable':'IslandCanvasCheck','CFBundlePackageType':'APPL','CFBundleVersion':'1','NSHighResolutionCapable':True,'UTExportedTypeDeclarations':types}))
INFO
    codesign --force --sign - "$APP"
    printf 'Created fixture app; not launched: %s\n' "$APP"
else
    xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/DesignerRender.swift -o "$STAGE/render"
    "$STAGE/render" "$OUTPUT"
fi
