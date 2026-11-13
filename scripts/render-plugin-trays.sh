#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:?Pass an output directory}";mkdir -p "$OUTPUT";OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d /private/tmp/island-plugin-render.XXXXXX)";trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Views.swift" <<'PY'
from pathlib import Path
import sys
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
m=Path('Island/Modules.swift').read_text();m=m[m.index('extension NotchViews'):m.index('@MainActor final class IslandModuleStore')]
g=Path('Island/Guidance.swift').read_text();g=g[g.index('struct IslandGuideTopic:'):g.index('struct IslandGuideContent:')]
d=Path('Island/ModulePreview.swift').read_text();d=d[d.index('enum IslandModuleGuide'):]
c=Path('Island/IslandShell.swift').read_text();c=c[c.index('enum IslandCompactKind'):c.index('struct IslandSurface:')]
t=Path('Island/Trays.swift').read_text().replace('static let shared=IslandActivityTrayStore()','static let shared=IslandActivityTrayStore(defaults:UserDefaults(suiteName:"IslandPluginRender.Fixture")!)')
a=Path('Island/AgentBridge.swift').read_text();event=a[a.index('    struct Event:'):a.index('    @Published var events:')]
p=Path('Island/PluginActivity.swift').read_text()
f='''
@MainActor final class IslandModuleStore:ObservableObject {
 static let shared=IslandModuleStore();@Published var preferences=IslandModulePreferences()
 var enabled:[NotchViews] { preferences.enabled };var defaultModule:NotchViews { preferences.start }
 func setDefault(_ value:NotchViews) { preferences.start=value };func setEnabled(_ module:NotchViews,_ enabled:Bool) {};func move(_ module:NotchViews,by:Int) {};func restore(_ value:IslandModulePreferences) { preferences=value }
}
@MainActor final class IslandAgentBridge:ObservableObject {
''' + event + '''
 @Published var events:[Event]=[];@Published var error:String?;func answer(_ event:Event,text:String)->Bool { false }
}
enum IslandHaptics { enum Event { case selection,confirmation };static func play(_ event:Event) {} }
@MainActor final class IslandSettingsController { static let shared=IslandSettingsController();func showModuleDesigner() {} }
@MainActor final class IslandLiveActivityClock { static let shared=IslandLiveActivityClock();func configure() {} }
'''
Path(sys.argv[1]).write_text('import Foundation\nimport SwiftUI\nimport Combine\n'+e+m+d+g+c+f+t+p)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/PluginTraysRender.swift -o "$STAGE/render"
"$STAGE/render" "$OUTPUT"
