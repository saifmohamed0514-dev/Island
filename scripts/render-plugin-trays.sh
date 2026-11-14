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
act=Path('Island/IslandShell.swift').read_text();act=act[act.index('struct IslandCompactActivity:'):act.index('struct IslandNowPlayingView:')]
f='''
@MainActor final class IslandModuleStore:ObservableObject {
 static let shared=IslandModuleStore();@Published var preferences=IslandModulePreferences()
 var enabled:[NotchViews] { preferences.enabled };var defaultModule:NotchViews { preferences.start }
 func setDefault(_ value:NotchViews) { preferences.start=value };func setEnabled(_ module:NotchViews,_ enabled:Bool) {};func move(_ module:NotchViews,by:Int) {};func restore(_ value:IslandModulePreferences) { preferences=value }
}
@MainActor final class IslandAgentBridge:ObservableObject {
 static let shared=IslandAgentBridge()
''' + event + '''
 @Published var events:[Event]=[];@Published var error:String?;var pending:[Event] { events.filter { $0.pending } };var activePluginProgress:Event? { nil };func answer(_ event:Event,text:String)->Bool { false }
}
enum IslandHaptics { enum Event { case selection,confirmation };static func play(_ event:Event) {} }
@MainActor final class IslandSettingsController { static let shared=IslandSettingsController();func showModuleDesigner(_ module:NotchViews?=nil) {} }
@MainActor final class IslandLiveActivityClock { static let shared=IslandLiveActivityClock();func configure() {} }
@MainActor final class IslandViewModel:ObservableObject { var closedNotchSize=CGSize(width:185,height:32);var effectiveClosedNotchHeight:CGFloat=32;func open() {} }
@MainActor final class IslandFocusTimer:ObservableObject { static let shared=IslandFocusTimer();var showCompletion=false;var label="25:00" }
@MainActor final class MusicManager:ObservableObject { static let shared=MusicManager();var isPlaying=true;var albumArt=NSImage(systemSymbolName:"music.note",accessibilityDescription:nil)!;func previousTrack() {};func nextTrack() {};func togglePlay() {} }
@MainActor final class IslandCoordinator:ObservableObject { static let shared=IslandCoordinator();var currentView:NotchViews = .home;var showingCanvasDetail=false;struct Peek { var icon="";var value:Double=0 };var sneakPeek=Peek() }
@MainActor final class BatteryStatusViewModel:ObservableObject { static let shared=BatteryStatusViewModel();var isCharging=false;var levelBattery:Double=84 }
func islandBatteryPercent(_ value:Double)->Int { Int(value) }
@MainActor final class IslandAgenda:ObservableObject { static let shared=IslandAgenda();struct Event {var startDate:Date;var endDate:Date};var events:[Event]=[] }
@MainActor final class IslandDevices:ObservableObject { static let shared=IslandDevices();struct Device {var battery:Int?};var devices:[Device]=[] }
@MainActor final class IslandNotices:ObservableObject { static let shared=IslandNotices();struct Notice {var read=false};var items:[Notice]=[] }

'''
Path(sys.argv[1]).write_text('import Foundation\nimport SwiftUI\nimport Combine\nimport CoreTransferable\nimport UniformTypeIdentifiers\n'+e+m+d+g+c+f+t+p+act)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/PluginTraysRender.swift -o "$STAGE/render"
"$STAGE/render" "$OUTPUT"
