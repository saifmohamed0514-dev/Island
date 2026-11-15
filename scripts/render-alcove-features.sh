#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:?Pass an output directory}";mkdir -p "$OUTPUT";OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d /private/tmp/island-features-render.XXXXXX)";trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Views.swift" <<'PY'
from pathlib import Path
import sys
a=Path('Island/Appearance.swift').read_text().replace('static let shared=IslandAppearanceStore()','static let shared=IslandAppearanceStore(defaults:fixtureDefaults)')
l=Path('Island/LockWidgets.swift').read_text();l=l[:l.index('@MainActor final class IslandLockScreenController')]+l[l.index('struct IslandLockWidgetsSettings:'):];l=l.replace('static let shared=IslandLockStore()','static let shared=IslandLockStore(defaults:fixtureDefaults)').replace('INFocusStatusCenter.default.authorizationStatus == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil','Optional(false)').replace('IOPSGetTimeRemainingEstimate()','Double(7200)')
c=Path('Island/CalendarExperience.swift').read_text().replace('static let shared=IslandCalendarStore()','static let shared=IslandCalendarStore(defaults:fixtureDefaults)').replace('agenda.store.calendars(for:.event)','agenda.fixtureCalendars')
u=Path('Island/CalendarUI.swift').read_text()
m=Path('Island/IslandShell.swift').read_text();m=m[m.index('struct IslandNowPlayingView:'):]
# No live device, account, app, capture, permission, audio or calendar-data access in fixture actions.
f='''
let fixtureDefaults=UserDefaults(suiteName:"IslandFeaturesRender.Fixture")!
@MainActor final class MusicManager:ObservableObject {
 static let shared=MusicManager();@Published var isPlayerIdle=false
 var isPlaying=true;var songTitle="A long song title · تجربة الموسيقى في الجزيرة";var artistName="Sample Artist";var album="Sample Album";var albumArt=NSImage(systemSymbolName:"music.note",accessibilityDescription:nil)!
 var elapsedTime=84.0;var songDuration=245.0;var playbackRate=1.0;var isShuffled=true;var repeatMode:RepeatMode = .all;var volume=0.6
 var playbackRateSupported=false;var isExplicit:Bool?;var trackURL:URL?;func openCurrentTrack() {};func setPlaybackRate(_ value:Double) {};var volumeControlSupported=true;var canFavoriteTrack=true;var isFavoriteTrack=false;var shuffleSupported=true;var repeatSupported=true;var supportsForward15=false;var supportsBackward15=false;var prohibitsSkip=false
 func previousTrack() {};func nextTrack() {};func togglePlay() {};func openMusicApp() {};func toggleShuffle() {};func toggleRepeat() {};func toggleFavoriteTrack() {};func seek(to:Double) {};func setVolume(to:Double) {};func skip(seconds:Double) {};func estimatedPlaybackPosition(at:Date)->Double { 84 }
}
@MainActor final class IslandViewModel:ObservableObject { var isBatteryPopoverActive=false,isHoveringCalendar=false }
@MainActor final class IslandSettingsController { static let shared=IslandSettingsController();func showPermissions(_ value:Permission?=nil) {} }
enum Permission { case music,spotify,calendar,notifications }
enum Defaults { enum Key { case mediaController };static subscript(_ key:Key)->Source { .nowPlaying };enum Source { case nowPlaying,appleMusic,spotify } }
struct IslandActivityInput:View { let middleClick:Bool;let horizontal:Bool;let onCycle:()->Void;let onSkip:(Bool)->Void;var body:some View { Color.clear } }
enum IslandHaptics { enum Event { case selection,confirmation,placement };static func play(_ event:Event) {} }
struct IslandAudioOutputView:View { var body:some View { Text("Sample audio output") } }
@MainActor final class BatteryStatusViewModel:ObservableObject { static let shared=BatteryStatusViewModel();var isCharging=false,isPluggedIn=false;var levelBattery:Float=84 }
func islandBatteryPercent(_ value:Float)->Int { Int(value) }
@MainActor final class IslandWeather:ObservableObject { static let shared=IslandWeather();struct Forecast { struct Current { var temperature_2m=24.0;var weather_code=1 };var current=Current() };var forecast:Forecast?=Forecast();static func condition(_ code:Int)->String { "Mostly clear" } }
@MainActor final class IslandAgenda:ObservableObject { static let shared=IslandAgenda();let store=EKEventStore();var calendarConnected=true;var events:[EKEvent]=[];var monthEvents:[EKEvent]=[];var fixtureCalendars:[EKCalendar]=[];func refresh() async {};func refreshMonth(containing:Date,force:Bool=false) async {} }
@MainActor final class IslandCalendarAlerts:ObservableObject { static let shared=IslandCalendarAlerts();var status="Reminders off" }
@MainActor final class IslandDevices:ObservableObject { static let shared=IslandDevices();struct Device { var name:String;var battery:Int? };var devices=[Device(name:"Sample AirPods",battery:72)] }
@MainActor final class IslandQuickActions:ObservableObject { static let shared=IslandQuickActions();var keepingAwake=false;func setAwake(_ value:Bool) {} }
@MainActor final class VolumeManager { static let shared=VolumeManager();var rawVolume:Float=0.6;func setAbsolute(_ value:Float) {} }
'''
Path(sys.argv[1]).write_text('import SwiftUI\nimport Foundation\nimport AppKit\nimport EventKit\n'+f+Path('IslandCore/models/PlaybackState.swift').read_text()+Path('Island/MediaState.swift').read_text()+a+Path('Island/IslandCalendarRules.swift').read_text()+c+u+l+m)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Views.swift" Tests/AlcoveFeaturesRender.swift -o "$STAGE/render"
"$STAGE/render" "$OUTPUT"
