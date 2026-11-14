import SwiftUI
import Combine
import CoreTransferable
import UniformTypeIdentifiers

enum IslandActivityTray:String,CaseIterable,Codable,Identifiable {
    case timer,music,wellbeing,agent,event,device,notice
    var id:String { rawValue }
    var title:String { switch self { case .timer:return "Focus timer";case .music:return "Now Playing";case .wellbeing:return "Wellbeing";case .agent:return "AI activity & questions";case .event:return "Upcoming events";case .device:return "Device batteries";case .notice:return "Island Inbox" } }
    var icon:String { switch self { case .timer:return "timer";case .music:return "music.note";case .wellbeing:return "drop.fill";case .agent:return "sparkles";case .event:return "calendar";case .device:return "headphones";case .notice:return "bell" } }
    var detail:String { switch self { case .timer:return "Time remaining while a timer runs. Hiding it keeps the timer running.";case .music:return "Artwork and playback status from your chosen player.";case .wellbeing:return "Today’s water count and goal. Click to open Wellbeing.";case .agent:return "Progress and questions sent by the Island plugin.";case .event:return "An event starting in the next 30 minutes.";case .device:return "Connected accessories and available battery levels.";case .notice:return "Unread notices in your Island Inbox." } }
    var module:NotchViews { switch self { case .timer:return .focus;case .music:return .home;case .wellbeing:return .health;case .agent:return .agents;case .event:return .calendar;case .device:return .devices;case .notice:return .inbox } }
    var kind:IslandCompactKind { switch self { case .timer:return .timer;case .music:return .music;case .wellbeing:return .wellbeing;case .agent:return .agent;case .event:return .event;case .device:return .device;case .notice:return .notice } }
}
extension UTType { static let islandActivityTray=UTType(exportedAs:"org.islandapp.activity-tray",conformingTo:.data) }
struct IslandActivityTrayTransfer:Codable,Transferable {
    let tray:IslandActivityTray
    static var transferRepresentation:some TransferRepresentation { CodableRepresentation(contentType:.islandActivityTray) }
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
    @discardableResult mutating func place(_ tray:IslandActivityTray,at index:Int)->Bool {
        normalize();guard order.indices.contains(index) else { return false }
        order.removeAll { $0==tray };order.insert(tray,at:min(index,order.count));enabled.append(tray);normalize();return true
    }
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
    func place(_ tray:IslandActivityTray,at index:Int) { if preferences.place(tray,at:index) { save() } }
    func restore(_ snapshot:IslandActivityTrayPreferences) { preferences=snapshot;preferences.normalize();save() }
    private func save() { defaults.set(try? JSONEncoder().encode(preferences),forKey:"island.trays.activities");NotificationCenter.default.post(name:Notification.Name("IslandActivityTraysChanged"),object:nil) }
}
struct IslandTraysSettings:View {
    @ObservedObject private var modules=IslandModuleStore.shared
    @ObservedObject private var activities=IslandActivityTrayStore.shared
    @AppStorage("island.live.rotate") private var rotate=false
    @AppStorage("island.live.musicQuickControls") private var musicQuickControls=true
    @AppStorage("island.live.aiPriority") private var aiPriority=true
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
                IslandCompactTrayEditor(preferences:activities.preferences,onPlace:{ tray,index in changeActivities { activities.place(tray,at:index) } },onRemove:{ tray in changeActivities { activities.set(tray,enabled:false) } })
                Toggle("Rotate available trays every 6 seconds",isOn:$rotate).onChange(of:rotate) { IslandLiveActivityClock.shared.configure() }
                Toggle("Prefer active AI work",isOn:$aiPriority)
                Text("Show reported AI progress before music and timers. Questions take priority while they need an answer. Your current hovered controls stay in place until you leave.").font(.caption).foregroundStyle(.secondary)
                Toggle("Music controls on hover",isOn:$musicQuickControls)
                Text("Hover over the music activity for play, pause and skip. Click its artwork to open the player. When off, your usual hover-to-open setting applies.").font(.caption).foregroundStyle(.secondary)
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


struct IslandCompactTrayEditor:View {
    let preferences:IslandActivityTrayPreferences
    let onPlace:(IslandActivityTray,Int)->Void
    let onRemove:(IslandActivityTray)->Void
    @State private var selected:IslandActivityTray = .timer
    @State private var targeted=false
    private var enabled:[IslandActivityTray] { preferences.order.filter { preferences.enabled.contains($0) } }
    private var preview:IslandActivityTray? { enabled.contains(selected) ? selected : enabled.first }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Arrange your compact trays").font(.headline)
            Text("Drag an activity into the black preview to add it. Drag its cards to change priority. Click a card for its module’s settings.").font(.caption).foregroundStyle(.secondary)
            VStack(spacing:12) {
                HStack(spacing:0) {
                    Label(preview?.title ?? "Drop here",systemImage:preview?.icon ?? "plus").font(.caption).lineLimit(1).frame(maxWidth:.infinity)
                    RoundedRectangle(cornerRadius:8).fill(.white.opacity(0.07)).frame(width:100,height:25).overlay { Text("Camera").font(.caption2).foregroundStyle(.gray) }.accessibilityHidden(true)
                    Text(preview == .timer ? "25:00" : preview == .wellbeing ? "3/8" : "Preview").font(.caption.monospacedDigit()).frame(maxWidth:.infinity)
                }.frame(height:30)
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:7) {
                        ForEach(enabled) { tray in
                            Button { selected=tray;IslandSettingsController.shared.showModuleDesigner(tray.module) } label: {
                                VStack(spacing:5) { Image(systemName:tray.icon);Text(tray.title).font(.caption2).lineLimit(1) }.frame(width:100,height:43).background(preview == tray ? .blue.opacity(0.3) : .white.opacity(0.08),in:RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain).help("Drag to reorder; click for settings").accessibilityLabel(tray.title+". Drag to reorder, click for settings.")
                            .draggable(IslandActivityTrayTransfer(tray:tray))
                            .dropDestination(for:IslandActivityTrayTransfer.self) { values,_ in
                                guard values.count==1,let index=preferences.order.firstIndex(of:tray) else { return false };selected=values[0].tray;onPlace(values[0].tray,index);return true
                            }
                            .contextMenu { Button("Hide this activity") { onRemove(tray) } }
                        }
                        if enabled.isEmpty { Label("Drop an activity here",systemImage:"plus.circle").font(.caption).frame(height:43).padding(.horizontal,12) }
                    }
                }
            }.padding(12).background(.black,in:RoundedRectangle(cornerRadius:18)).foregroundStyle(.white)
            .overlay { RoundedRectangle(cornerRadius:18).stroke(targeted ? Color.blue : .clear,lineWidth:2) }
            .dropDestination(for:IslandActivityTrayTransfer.self) { values,_ in guard values.count==1 else { return false };selected=values[0].tray;onPlace(values[0].tray,preferences.order.count-1);return true } isTargeted:{ targeted=$0 }
            .accessibilityLabel("Interactive compact Island preview. Sample content.")
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:7) {
                    ForEach(IslandActivityTray.allCases) { tray in
                        Button { selected=tray;if !preferences.enabled.contains(tray) { onPlace(tray,preferences.order.firstIndex(of:tray) ?? 0) } } label:{ Label(tray.title,systemImage:preferences.enabled.contains(tray) ? "checkmark.circle" : "plus.circle").font(.caption).padding(8).background(.secondary.opacity(0.08),in:Capsule()) }.buttonStyle(.plain).draggable(IslandActivityTrayTransfer(tray:tray)).help("Drag into the preview, or click to add")
                    }
                }
            }
            Text("The real Island shows one available activity at a time. Turn on rotation to cycle through them. The arrows below also work without dragging.").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical,6)
    }
}
