import SwiftUI
import AppKit
import Intents
import IOKit.ps

struct IslandLockPreferences:Codable,Equatable {
    static let available=["music","focus","weather","battery","devices","calendar"]
    var enabled=false
    var widgets=available
    var style="glass"
    var offset=0.0
    var privateDetails=false
    var showVolume=false
    var hideInactiveMusic=true
    var totalDuration=true
    var showArtwork=true
    var allDisplays=false
    var keepAwakeControl=true
    mutating func normalize() {
        var seen=Set<String>();widgets=widgets.filter { Self.available.contains($0) && seen.insert($0).inserted }
        if widgets.contains("music") { widgets.removeAll { $0=="music" };widgets.insert("music",at:0) }
        if !["glass","clear","solid"].contains(style) { style="glass" }
        offset=offset.isFinite ? min(200,max(-120,offset)) : 0
    }
    func panelFrame(screen:CGRect)->CGRect {
        let width=max(240,min(660,screen.width-48))
        let columns=max(1,min(3,Int((width-20)/182)))
        let small=widgets.filter { $0 != "music" }.count
        let rows=(small+columns-1)/columns
        let naturalHeight=32+(widgets.contains("music") ? 138 : 0)+Double(rows)*108+(keepAwakeControl ? 34 : 0)
        let height=min(max(100,screen.height*0.48),max(100,naturalHeight))
        let y=min(max(24,screen.height*0.34+offset),max(24,screen.height-height-60))
        return CGRect(x:screen.midX-width/2,y:screen.minY+y,width:width,height:height)
    }

    static func batteryTime(_ seconds:Double)->String? {
        guard seconds.isFinite,seconds>0,seconds<7*86400 else { return nil }
        let minutes=Int(seconds/60);guard minutes>0 else { return nil }
        return minutes>=60 ? "\(minutes/60)h \(minutes%60)m remaining" : "\(minutes)m remaining"
    }
}
@MainActor final class IslandLockStore:ObservableObject {
    static let shared=IslandLockStore()
    @Published private(set) var preferences:IslandLockPreferences
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        var p=defaults.data(forKey:"island.lock.preferences").flatMap { try? JSONDecoder().decode(IslandLockPreferences.self,from:$0) } ?? IslandLockPreferences()
        p.normalize();preferences=p
    }
    func set<T>(_ path:WritableKeyPath<IslandLockPreferences,T>,_ value:T) {
        var p=preferences;p[keyPath:path]=value;p.normalize();guard p != preferences else { return }
        preferences=p;defaults.set(try? JSONEncoder().encode(p),forKey:"island.lock.preferences")
        NotificationCenter.default.post(name:Notification.Name("IslandLockWidgetsChanged"),object:nil)
    }
    func binding<T>(_ path:WritableKeyPath<IslandLockPreferences,T>)->Binding<T> { Binding(get:{ self.preferences[keyPath:path] },set:{ self.set(path,$0) }) }
    func toggle(_ widget:String,_ enabled:Bool) {
        var widgets=preferences.widgets
        if enabled,!widgets.contains(widget) { widgets.append(widget) } else if !enabled { widgets.removeAll { $0==widget } }
        set(\.widgets,widgets)
    }
    func move(_ widget:String,by delta:Int) {
        guard widget != "music" else { return }
        var widgets=preferences.widgets
        let positions=widgets.indices.filter { widgets[$0] != "music" }
        guard let index=positions.firstIndex(where:{ widgets[$0]==widget }),positions.indices.contains(index+delta) else { return }
        widgets.swapAt(positions[index],positions[index+delta]);set(\.widgets,widgets)
    }
}
@MainActor final class IslandLockScreenController {
    static let shared=IslandLockScreenController()
    private var windows:[IslandPanel]=[]
    private var locked=false
    private var observer:NSObjectProtocol?
    private init() {
        observer=NotificationCenter.default.addObserver(forName:Notification.Name("IslandLockWidgetsChanged"),object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in if self?.locked == true { self?.present() } }
        }
    }
    func present() {
        dismiss();locked=true
        let p=IslandLockStore.shared.preferences
        guard p.enabled,!p.widgets.isEmpty,!IslandSnooze.shared.active else { return }
        let selected=NSScreen.screens.first { $0.displayUUID==IslandCoordinator.shared.selectedScreenUUID } ?? NSScreen.main
        let screens=p.allDisplays ? NSScreen.screens : selected.map { [$0] } ?? []
        for screen in screens {
            let panel=IslandPanel(contentRect:p.panelFrame(screen:screen.frame),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.contentView=NSHostingView(rootView:ScrollView { IslandLockWidgetsView() })
            panel.enableSkyLight();panel.orderFrontRegardless();windows.append(panel)
        }
    }
    func dismiss() {
        for window in windows { window.disableSkyLight();window.orderOut(nil);window.close() }
        windows=[];locked=false
    }
}
struct IslandLockWidgetRow:Identifiable {
    let widget:String
    let section:String
    var id:String { section+"."+widget }
}
struct IslandLockWidgetsSettings:View {
    @ObservedObject private var model=IslandLockStore.shared
    @State private var preview=false
    var body:some View {
        Form {
            Section("While your Mac is locked") {
                Toggle("Show lock-screen widgets",isOn:model.binding(\.enabled))
                if model.preferences.widgets.isEmpty { Text("Choose at least one widget below.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Show on every display",isOn:model.binding(\.allDisplays))
                Toggle("Show Keep Awake control",isOn:model.binding(\.keepAwakeControl))
                Picker("Appearance",selection:model.binding(\.style)) { Text("System glass").tag("glass");Text("Clear glass").tag("clear");Text("Quiet solid").tag("solid") }
                Slider(value:model.binding(\.offset),in:-120...200,step:4) { Text("Vertical offset") }
                Button("Preview your widgets") { preview=true }
            }
            Section("Choose widgets") {
                ForEach(IslandLockPreferences.available.map { IslandLockWidgetRow(widget:$0,section:"choice") }) { row in
                    Toggle(row.widget.capitalized,isOn:Binding(get:{ model.preferences.widgets.contains(row.widget) },set:{ model.toggle(row.widget,$0) }))
                }
            }
            Section("Arrange small widgets") {
                ForEach(model.preferences.widgets.filter { $0 != "music" }.map { IslandLockWidgetRow(widget:$0,section:"order") }) { row in
                    HStack {
                        Text(row.widget.capitalized);Spacer()
                        Button { model.move(row.widget,by:-1) } label:{ Image(systemName:"arrow.up") }.accessibilityLabel("Move "+row.widget+" earlier").disabled(model.preferences.widgets.filter { $0 != "music" }.first==row.widget)
                        Button { model.move(row.widget,by:1) } label:{ Image(systemName:"arrow.down") }.accessibilityLabel("Move "+row.widget+" later").disabled(model.preferences.widgets.filter { $0 != "music" }.last==row.widget)
                    }
                }
                Text("Music stays above the smaller cards. The arrows change the order of the other widgets.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Now Playing") {
                Toggle("Hide when nothing is playing",isOn:model.binding(\.hideInactiveMusic))
                Toggle("Show artwork",isOn:model.binding(\.showArtwork))
                Toggle("Show output volume",isOn:model.binding(\.showVolume))
                Toggle("Show total duration",isOn:model.binding(\.totalDuration))
            }
            Section("Personal details") {
                Toggle("Show track names, event names and device names",isOn:model.binding(\.privateDetails))
                Text("Off keeps these details out of the locked screen. Media controls remain available. Widgets never unlock your Mac or change its authentication.").font(.caption).foregroundStyle(.secondary)
                Button("Manage Calendar and Focus access…") { IslandSettingsController.shared.showPermissions() }
            }
        }.formStyle(.grouped).sheet(isPresented:$preview) {
            VStack(spacing:12) { HStack { Text("Your lock-screen widgets").font(.headline);Spacer();Button("Done") { preview=false }.keyboardShortcut(.cancelAction) };ScrollView { IslandLockWidgetsView() } }.padding(20).frame(width:700,height:470)
        }
    }
}
struct IslandLockWidgetsView:View {
    @ObservedObject private var settings=IslandLockStore.shared
    @ObservedObject private var music=MusicManager.shared
    @ObservedObject private var battery=BatteryStatusViewModel.shared
    @ObservedObject private var weather=IslandWeather.shared
    @ObservedObject private var agenda=IslandAgenda.shared
    @ObservedObject private var calendars=IslandCalendarStore.shared
    @ObservedObject private var devices=IslandDevices.shared
    @ObservedObject private var quick=IslandQuickActions.shared
    @AppStorage("island.weather.fahrenheit") private var fahrenheit=false
    private var p:IslandLockPreferences { settings.preferences }
    var body:some View {
        VStack(spacing:12) {
                if p.widgets.contains("music"),!p.hideInactiveMusic || !music.isPlayerIdle { musicCard }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:12) {
                    ForEach(p.widgets.filter { $0 != "music" },id:\.self) { widget in smallCard(widget).frame(height:76).padding(10).frame(maxWidth:.infinity).modifier(IslandLockCardBackground(style:p.style)) }
                }
                if p.keepAwakeControl {
                    HStack { Spacer();Toggle("Keep Awake",isOn:Binding(get:{ quick.keepingAwake },set:{ quick.setAwake($0) })).toggleStyle(.switch).controlSize(.small) }.padding(10).modifier(IslandLockCardBackground(style:p.style))
                }
            }.padding(16)
    }
    private var musicCard:some View {
        VStack(spacing:10) {
            HStack(spacing:12) {
                if p.showArtwork { Image(nsImage:music.albumArt).resizable().scaledToFill().frame(width:46,height:46).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true) }
                VStack(alignment:.leading,spacing:3) { Text(p.privateDetails ? music.songTitle : music.isPlayerIdle ? "Not Playing" : "Now Playing").font(.headline).lineLimit(1);if p.privateDetails && !music.artistName.isEmpty { Text(music.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                Spacer()
                Button { music.previousTrack() } label: { Image(systemName:"backward.fill") }.accessibilityLabel("Previous track")
                Button { music.togglePlay() } label: { Image(systemName:music.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel("Play or pause")
                Button { music.nextTrack() } label: { Image(systemName:"forward.fill") }.accessibilityLabel("Next track")
            }.buttonStyle(.plain)
            if !music.isPlayerIdle { TimelineView(.periodic(from:.now,by:1)) { context in
                HStack(spacing:8) { Text(Self.time(music.estimatedPlaybackPosition(at:context.date))).font(.caption2).monospacedDigit();ProgressView(value:min(max(0,music.estimatedPlaybackPosition(at:context.date)),max(1,music.songDuration)),total:max(1,music.songDuration));if p.totalDuration { Text(Self.time(music.songDuration)).font(.caption2).monospacedDigit() } }
            } }
            if p.showVolume { HStack { Image(systemName:"speaker.fill");Slider(value:Binding(get:{ Double(VolumeManager.shared.rawVolume) },set:{ VolumeManager.shared.setAbsolute(Float($0)) }),in:0...1).controlSize(.small);Image(systemName:"speaker.wave.3.fill") }.font(.caption).accessibilityLabel("System volume") }
        }.padding(16).modifier(IslandLockCardBackground(style:p.style))
    }
    @ViewBuilder private func smallCard(_ kind:String)->some View {
        switch kind {
        case "focus":
            TimelineView(.periodic(from:.now,by:30)) { _ in
                let shared=INFocusStatusCenter.default.authorizationStatus == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
                VStack(spacing:7) { Image(systemName:"moon.fill").foregroundStyle(.purple);Text(shared == true ? "Focus is on" : shared == false ? "Focus is off" : "Focus not shared").font(.callout.weight(.medium));Text("System Focus").font(.caption2).foregroundStyle(.secondary) }
            }
        case "weather":
            VStack(spacing:5) { Image(systemName:"cloud.sun.fill").foregroundStyle(.orange);if let current=weather.forecast?.current { Text("\(Int((fahrenheit ? current.temperature_2m*9/5+32 : current.temperature_2m).rounded()))°").font(.title2.weight(.semibold));Text(IslandWeather.condition(current.weather_code)).font(.caption2) } else { Text("Weather not set").font(.caption) } }
        case "battery":
            TimelineView(.periodic(from:.now,by:60)) { _ in VStack(spacing:5) { Image(systemName:battery.isCharging ? "battery.100.bolt" : "battery.100").foregroundStyle(.green);Text("\(islandBatteryPercent(battery.levelBattery))%").font(.title2.weight(.semibold));Text(battery.isPluggedIn ? "Plugged in" : IslandLockPreferences.batteryTime(IOPSGetTimeRemainingEstimate()) ?? "On battery").font(.caption2).lineLimit(1) } }
        case "devices":
            VStack(spacing:6) { Image(systemName:"headphones").foregroundStyle(.cyan);Text(p.privateDetails ? devices.devices.first?.name ?? "No devices" : devices.devices.isEmpty ? "No devices" : "Connected").font(.callout.weight(.medium)).lineLimit(1);Text(devices.devices.compactMap(\.battery).min().map { "\($0)% battery" } ?? "Available device levels").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        case "calendar":
            TimelineView(.periodic(from:.now,by:60)) { context in
                VStack(spacing:5) { Image(systemName:"calendar").foregroundStyle(.orange);if let event=calendars.visible(agenda.events).first(where:{ $0.endDate>context.date }) { Text(p.privateDetails ? event.title ?? "Event" : "Upcoming event").font(.callout.weight(.medium)).lineLimit(1);Text(event.startDate,style:.time).font(.caption) } else { Text(context.date,format:.dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.callout);Text(agenda.calendarConnected ? "Your day is clear" : "Calendar not connected").font(.caption2).foregroundStyle(.secondary) } }
            }
        default:EmptyView()
        }
    }
    private static func time(_ value:Double)->String { guard value.isFinite,value>=0 else { return "0:00" };let seconds=Int(min(value,604800));return "\(seconds/60):\(String(format:"%02d",seconds%60))" }
}
struct IslandLockCardBackground:ViewModifier {
    let style:String
    @Environment(\.colorScheme) private var colorScheme
    private var label:Color { colorScheme == .dark ? .white : .black }
    func body(content:Content)->some View {
        if style == "solid" { content.foregroundStyle(label).background(.background.opacity(0.94),in:RoundedRectangle(cornerRadius:22)) }
        else if #available(macOS 26.0,*) { content.foregroundStyle(label).glassEffect(style == "clear" ? .clear : .regular,in:RoundedRectangle(cornerRadius:22)) }
        else { content.foregroundStyle(label).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22)) }
    }
}
