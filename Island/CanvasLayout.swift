import SwiftUI
import Combine

struct IslandCanvasPreferences:Codable,Equatable {
    var enabled=false
    var slots:[NotchViews?]=[.home,.shelf,.focus,nil]
    mutating func normalize() {
        slots=Array((slots+Array(repeating:nil,count:4)).prefix(4))
        var seen=Set<NotchViews>()
        for index in slots.indices { if let module=slots[index],!seen.insert(module).inserted { slots[index]=nil } }
    }
    static func initial(modules:[NotchViews])->IslandCanvasPreferences {
        var result=IslandCanvasPreferences()
        let candidates=modules.filter { $0 != .dashboard }
        result.slots=Array((candidates.isEmpty ? [.dashboard] : candidates).prefix(3)).map(Optional.some)
        result.normalize();return result
    }
    var modules:[NotchViews] { slots.compactMap { $0 } }
    func showsLayout(currentView:NotchViews,showingDetail:Bool)->Bool { enabled && currentView == .dashboard && !showingDetail }
    @discardableResult mutating func place(_ module:NotchViews,at index:Int)->Bool {
        guard (0..<4).contains(index) else { return false };normalize()
        if let source=slots.firstIndex(of:module) { slots.swapAt(source,index) }
        else { slots[index]=module }
        enabled=true;return true
    }
    @discardableResult mutating func remove(_ module:NotchViews)->Bool {
        normalize();guard let index=slots.firstIndex(of:module) else { return false };slots[index]=nil;return true
    }
    static func title(_ index:Int)->String { ["Top left","Top right","Bottom left","Bottom right"].indices.contains(index) ? ["Top left","Top right","Bottom left","Bottom right"][index] : "Position" }
}
struct IslandDesignerSnapshot:Codable,Equatable {
    var modules:IslandModulePreferences
    var canvas:IslandCanvasPreferences
}
@MainActor final class IslandCanvasStore:ObservableObject {
    static let shared=IslandCanvasStore()
    @Published private(set) var preferences:IslandCanvasPreferences
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        preferences=defaults.data(forKey:"island.canvas.layout").flatMap { try? JSONDecoder().decode(IslandCanvasPreferences.self,from:$0) } ?? .initial(modules:IslandModuleStore.shared.enabled)
        preferences.normalize()
    }
    func place(_ module:NotchViews,at index:Int) {
        let adding = !preferences.modules.contains(module)
        if preferences.place(module,at:index) { save();activate(enabling:adding ? [module] : []) }
    }
    func remove(_ module:NotchViews) { if preferences.remove(module) { save() } }
    func setEnabled(_ enabled:Bool) { preferences.enabled=enabled;save();if enabled { activate() } }
    func template(_ name:String) {
        switch name {
        case "Work":preferences.slots=[.calendar,.tasks,.focus,.notes]
        case "Simple":preferences.slots=[.home,.focus,nil,nil]
        default:preferences.slots=[.home,.shelf,.focus,.notes]
        }
        preferences.enabled=true;preferences.normalize();save();activate(enabling:preferences.modules)
    }
    func restore(_ value:IslandCanvasPreferences) { preferences=value;preferences.normalize();save();IslandCoordinator.shared.showingCanvasDetail=false }
    private func activate(enabling modules:[NotchViews]=[]) {
        IslandModuleStore.shared.enableForCanvas(modules)
        IslandCoordinator.shared.currentView = .dashboard
        IslandCoordinator.shared.showingCanvasDetail=false
    }
    private func save() { defaults.set(try? JSONEncoder().encode(preferences),forKey:"island.canvas.layout") }
}

struct IslandCanvasLiveView:View {
    @ObservedObject private var layout=IslandCanvasStore.shared
    @ObservedObject private var modules=IslandModuleStore.shared
    @ObservedObject private var music=MusicManager.shared
    @ObservedObject private var focus=IslandFocusTimer.shared
    @ObservedObject private var shelf=ShelfStateViewModel.shared
    @ObservedObject private var agenda=IslandAgenda.shared
    @ObservedObject private var weather=IslandWeather.shared
    @ObservedObject private var devices=IslandDevices.shared
    @ObservedObject private var bridge=IslandAgentBridge.shared
    @ObservedObject private var notices=IslandNotices.shared
    @ObservedObject private var usage=IslandUsageTracker.shared
    @State private var system=IslandSystemSample()
    var body:some View {
        Group {
            if layout.preferences.modules.isEmpty {
                Button { IslandSettingsController.shared.showModuleDesigner() } label: { VStack(spacing:8) { Image(systemName:"square.grid.2x2").font(.title);Text("Make this space yours").font(.headline);Text("Add modules in Settings").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity) }.buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                        ForEach(0..<4,id:\.self) { index in
                            if let module=layout.preferences.slots[index] {
                                Button { open(module) } label: {
                                    HStack(spacing:12) {
                                        Image(systemName:module.icon).font(.system(size:20)).foregroundStyle(.cyan).frame(width:28)
                                        VStack(alignment:.leading,spacing:4) { Text(module.title).font(.caption).foregroundStyle(.secondary);Text(modules.enabled.contains(module) ? value(module,at:context.date) : "Off · click to configure").font(.system(size:14,weight:.medium,design:.rounded)).lineLimit(1).monospacedDigit() }
                                        Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                                    }.padding(.horizontal,14).frame(height:62).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
                                }.buttonStyle(.plain).accessibilityLabel(module.title+", "+value(module,at:context.date)+". Open full module.")
                            } else { Color.clear.frame(height:62).accessibilityHidden(true) }
                        }
                    }
                }
            }
        }.frame(height:134)
        .task(id:layout.preferences.slots.map { $0?.rawValue ?? "" }.joined(separator:",")+"|"+modules.enabled.map(\.rawValue).joined(separator:",")) {
            let active=layout.preferences.modules.filter { modules.enabled.contains($0) }
            if active.contains(where:{ [.calendar,.tasks,.day].contains($0) }) { await agenda.refresh() }
            if active.contains(.devices) { devices.refresh() }
            while !Task.isCancelled { if layout.preferences.modules.contains(.system) && modules.enabled.contains(.system) { system.update() };try? await Task.sleep(for:.seconds(1)) }
        }
    }
    private func open(_ module:NotchViews) {
        guard modules.enabled.contains(module) else { IslandSettingsController.shared.showModuleDesigner(module);return }
        IslandCoordinator.shared.showingCanvasDetail=true
        IslandCoordinator.shared.currentView=module
    }
    private func value(_ module:NotchViews,at date:Date)->String {
        switch module {
        case .home:return music.isPlayerIdle ? "Not Playing" : music.songTitle
        case .focus:return focus.showCompletion ? "Done" : focus.label
        case .shelf:return shelf.items.isEmpty ? "Drop something here" : "\(shelf.items.count) items"
        case .notes:
            let data=UserDefaults.standard.data(forKey:"island.notes.collection")
            let saved=data.flatMap { try? JSONDecoder().decode([IslandNotesStore.Note].self,from:$0) } ?? []
            return "\(saved.filter { $0.deleted == nil }.count) notes"
        case .calendar:return agenda.calendarConnected ? agenda.events.first?.title ?? "No upcoming events" : "Connect Calendar"
        case .tasks:return agenda.remindersConnected ? "\(agenda.reminders.filter { !$0.isCompleted }.count) to do" : "Connect Reminders"
        case .weather:
            guard let current=weather.forecast?.current else { return "Open for forecast" }
            let degrees=UserDefaults.standard.bool(forKey:"island.weather.fahrenheit") ? current.temperature_2m*9/5+32 : current.temperature_2m
            guard degrees.isFinite,abs(degrees)<1000 else { return "Weather unavailable" }
            return "\(Int(degrees.rounded()))° · "+IslandWeather.condition(current.weather_code)
        case .system:return system.cpu.map { "CPU \(Int($0*100))%" } ?? "Reading…"
        case .usage:return "\(Int(usage.entries.values.reduce(0) { $0+$1.seconds }/60)) minutes today"
        case .devices:return devices.devices.isEmpty ? "Open devices" : "\(devices.devices.count) connected"
        case .agents:return bridge.pending.isEmpty ? "\(bridge.sessions.count) sessions" : "\(bridge.pending.count) waiting"
        case .inbox:return "\(notices.items.filter { !$0.read }.count) unread Island alerts"
        case .day:
            let start=Calendar.current.startOfDay(for:date),end=Calendar.current.date(byAdding:.day,value:1,to:start) ?? start.addingTimeInterval(86400)
            return "\(Int(min(100,max(0,date.timeIntervalSince(start)/end.timeIntervalSince(start)*100))))% of today"
        case .dashboard:return date.formatted(date:.omitted,time:.shortened)
        case .health:return "Make room for a pause"
        case .launcher:return "Your shortcuts"
        case .code:return "Open reviews and issues"
        case .translation:return UserDefaults.standard.string(forKey:"island.translate.language") ?? "Choose a language"
        case .windows:return "Arrange a window"
        case .files:return "Choose files"
        case .mirror:return "Tap to open Mirror"
        }
    }
}
