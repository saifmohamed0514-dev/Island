import SwiftUI
import Combine

enum IslandActivityTray:String,CaseIterable,Codable,Identifiable {
    case timer,music,wellbeing,agent,event,device,notice
    var id:String { rawValue }
    var title:String { switch self { case .timer:return "Focus timer";case .music:return "Now Playing";case .wellbeing:return "Wellbeing";case .agent:return "AI activity & questions";case .event:return "Upcoming events";case .device:return "Device batteries";case .notice:return "Island Inbox" } }
    var icon:String { switch self { case .timer:return "timer";case .music:return "music.note";case .wellbeing:return "drop.fill";case .agent:return "sparkles";case .event:return "calendar";case .device:return "headphones";case .notice:return "bell" } }
    var detail:String { switch self { case .timer:return "Time remaining while a timer runs. Hiding it keeps the timer running.";case .music:return "Artwork and playback status from your chosen player.";case .wellbeing:return "Today’s water count and goal. Click to open Wellbeing.";case .agent:return "Progress and questions sent by the Island plugin.";case .event:return "An event starting in the next 30 minutes.";case .device:return "Connected accessories and available battery levels.";case .notice:return "Unread notices in your Island Inbox." } }
    var kind:IslandCompactKind { switch self { case .timer:return .timer;case .music:return .music;case .wellbeing:return .wellbeing;case .agent:return .agent;case .event:return .event;case .device:return .device;case .notice:return .notice } }
}
struct IslandActivityTrayPreferences:Codable,Equatable {
    var order=IslandActivityTray.allCases
    var enabled:[IslandActivityTray]=[.timer,.music,.agent]
    mutating func normalize() {
        var seen=Set<IslandActivityTray>();order=(order+IslandActivityTray.allCases).filter { seen.insert($0).inserted }
        enabled=order.filter { enabled.contains($0) }
    }
    mutating func set(_ tray:IslandActivityTray,enabled value:Bool) { if value { enabled.append(tray) } else { enabled.removeAll { $0==tray } };normalize() }
    mutating func move(_ tray:IslandActivityTray,by delta:Int) { normalize();guard let index=order.firstIndex(of:tray) else { return };order.swapAt(index,max(0,min(order.count-1,index+delta)));normalize() }
    func arrange(_ values:[IslandCompactKind])->[IslandCompactKind] { order.filter { enabled.contains($0) && values.contains($0.kind) }.map(\.kind) }
    static func migrated(_ defaults:UserDefaults)->Self {
        var result=Self()
        for (tray,key) in [(IslandActivityTray.event,"island.live.calendar"),(.device,"island.live.devices"),(.notice,"island.live.notices")] where defaults.bool(forKey:key) { result.enabled.append(tray) }
        result.normalize();return result
    }
}
@MainActor final class IslandActivityTrayStore:ObservableObject {
    static let shared=IslandActivityTrayStore()
    @Published private(set) var preferences:IslandActivityTrayPreferences
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        preferences=defaults.data(forKey:"island.trays.activities").flatMap { try? JSONDecoder().decode(IslandActivityTrayPreferences.self,from:$0) } ?? .migrated(defaults)
        preferences.normalize()
    }
    func set(_ tray:IslandActivityTray,enabled:Bool) { preferences.set(tray,enabled:enabled);save() }
    func move(_ tray:IslandActivityTray,by delta:Int) { preferences.move(tray,by:delta);save() }
    func restore(_ snapshot:IslandActivityTrayPreferences) { preferences=snapshot;preferences.normalize();save() }
    private func save() { defaults.set(try? JSONEncoder().encode(preferences),forKey:"island.trays.activities");NotificationCenter.default.post(name:Notification.Name("IslandActivityTraysChanged"),object:nil) }
}
struct IslandTraysSettings:View {
    @ObservedObject private var modules=IslandModuleStore.shared
    @ObservedObject private var activities=IslandActivityTrayStore.shared
    @AppStorage("island.live.rotate") private var rotate=false
    @State private var mode=0
    @State private var query=""
    init(initialTab:Int=0) { _mode=State(initialValue:initialTab) }
    @State private var undoModules:IslandModulePreferences?
    @State private var undoActivities:IslandActivityTrayPreferences?
    var body:some View {
        Form {
            Section {
                Text("Your Island. Your trays.").font(.title2.weight(.semibold))
                Text("Choose the tools inside Island and the activities beside the camera. Removing a tray keeps its saved content.").foregroundStyle(.secondary)
                Button("Arrange the interactive preview…") { IslandSettingsController.shared.showModuleDesigner() }
            }
            Section { Picker("Which trays",selection:$mode) { Text("Inside Island").tag(0);Text("While closed").tag(1) }.pickerStyle(.segmented) }
            if mode==0 { Section("Inside the opened Island") {
                Picker("Open with",selection:Binding(get:{ modules.defaultModule },set:{ value in changeModules { modules.setDefault(value) } })) { ForEach(modules.enabled) { Text($0.title).tag($0) } }
                Text("The first five enabled tools appear in the top strip; the rest are under More. Use the arrows to change their order.").font(.caption).foregroundStyle(.secondary)
                TextField("Find a tool",text:$query).textFieldStyle(.roundedBorder)
                ForEach(modules.preferences.order.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || IslandGuideCatalog.module($0).matches(query) }) { module in
                    HStack(spacing:10) {
                        Toggle(isOn:Binding(get:{ modules.enabled.contains(module) },set:{ value in changeModules { modules.setEnabled(module,value) } })) { Label(module.title,systemImage:module.icon) }.disabled(modules.enabled.count==1 && modules.enabled.contains(module))
                        Spacer(minLength:4)
                        orderButtons(title:module.title,index:modules.preferences.order.firstIndex(of:module) ?? 0,count:modules.preferences.order.count) { delta in changeModules { modules.move(module,by:delta) } }
                    }
                }
                if undoModules != nil { Button("Undo tool changes") { if let undoModules { modules.restore(undoModules);self.undoModules=nil } } }
            }
            } else { Section("While Island is closed") {
                Toggle("Rotate available trays every 6 seconds",isOn:$rotate).onChange(of:rotate) { IslandLiveActivityClock.shared.configure() }
                Text("Only enabled modules can supply activity. For example, enable Wellbeing under Inside Island, then add its activity here. Priority follows this order when rotation is off.").font(.caption).foregroundStyle(.secondary)
                ForEach(activities.preferences.order) { tray in
                    HStack(spacing:10) {
                        Toggle(isOn:Binding(get:{ activities.preferences.enabled.contains(tray) },set:{ value in changeActivities { activities.set(tray,enabled:value) } })) { VStack(alignment:.leading,spacing:4) { Label(tray.title,systemImage:tray.icon);Text(tray.detail).font(.caption).foregroundStyle(.secondary) } }
                        Spacer(minLength:4)
                        orderButtons(title:tray.title,index:activities.preferences.order.firstIndex(of:tray) ?? 0,count:activities.preferences.order.count) { delta in changeActivities { activities.move(tray,by:delta) } }
                    }.padding(.vertical,3)
                }
                if undoActivities != nil { Button("Undo activity changes") { if let undoActivities { activities.restore(undoActivities);self.undoActivities=nil } } }
                Text("Volume/brightness changes and battery notices are controlled in System Controls. Hiding a running timer’s activity does not stop the timer.").font(.caption).foregroundStyle(.secondary)
            } }
        }.formStyle(.grouped)
    }
    private func changeModules(_ action:()->Void) { undoModules=modules.preferences;action();IslandHaptics.play(.selection) }
    private func changeActivities(_ action:()->Void) { undoActivities=activities.preferences;action();IslandHaptics.play(.selection) }
    private func orderButtons(title:String,index:Int,count:Int,move:@escaping(Int)->Void)->some View {
        HStack(spacing:5) {
            Button { move(-1) } label:{ Image(systemName:"chevron.up") }.disabled(index==0).accessibilityLabel("Move "+title+" earlier")
            Button { move(1) } label:{ Image(systemName:"chevron.down") }.disabled(index==count-1).accessibilityLabel("Move "+title+" later")
        }.buttonStyle(.borderless)
    }
}
