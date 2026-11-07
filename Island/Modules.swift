import SwiftUI
import Combine
import Defaults

// Pure duration helpers shared by the dial, presets and tests.
enum IslandPresetRules {
    static func sanitize(_ values: [Int]) -> [Int] {
        let valid = Array(Set(values.filter { (1...1440).contains($0) })).sorted()
        return valid.isEmpty ? [25] : Array(valid.prefix(12))
    }
}
enum IslandDial {
    static func minutes(x: Double, y: Double, maximum: Double) -> Int {
        guard x.isFinite, y.isFinite, maximum.isFinite else { return 1 }
        var angle = atan2(y, x) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let limit = max(1, min(1440, maximum))
        return max(1, min(Int(limit), Int((angle / (2 * .pi) * limit).rounded())))
    }
}

enum IslandCycleRules {
    static func next(phase: String, completed: Int, work: Double, short: Double, long: Double) -> (phase: String, completed: Int, minutes: Double) {
        func duration(_ value: Double, fallback: Double) -> Double { value.isFinite && value >= 1 ? min(1440,value) : fallback }
        if phase == "Focus" {
            let count = (max(0,min(1000000,completed)) + 1) % 1000000
            return (count % 4 == 0 ? "Long Break" : "Break", count, count % 4 == 0 ? duration(long,fallback:15) : duration(short,fallback:5))
        }
        return ("Focus",max(0,completed),duration(work,fallback:25))
    }
}

struct IslandDialDrag {
    var previous: Double?
    var accumulated = 0.0
    mutating func value(x: Double, y: Double, current: Double, maximum: Double) -> Int? {
        guard x.isFinite, y.isFinite, hypot(x,y) >= 30, maximum.isFinite else { return nil }
        let limit = min(1440, max(1,maximum))
        var angle = atan2(y,x) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        func delta(_ a: Double, _ b: Double) -> Double {
            var value = b - a
            if value > .pi { value -= 2 * .pi }; if value < -.pi { value += 2 * .pi }
            return value
        }
        if let previous { accumulated += delta(previous,angle) / (2 * .pi) * limit }
        else {
            let currentAngle = min(1,max(0,current/limit)) * 2 * .pi
            accumulated = abs(delta(currentAngle,angle)) < 0.25 ? current : angle / (2 * .pi) * limit
        }
        accumulated = min(limit,max(1,accumulated)); previous = angle
        return Int(accumulated.rounded())
    }
}

extension NotchViews {
    var title:String { NSLocalizedString(englishTitle,comment:"Island module") }
    private var englishTitle: String {
        switch self {
        case .home: return "Now Playing"
        case .shelf: return "File Tray"
        case .focus: return "Focus"
        case .notes: return "Notes"
        case .dashboard: return "Dashboard"
        case .weather: return "Weather"
        case .health: return "Wellbeing"
        case .system: return "System Monitor"
        case .usage: return "Screen Time"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .day: return "Day Progress"
        case .launcher: return "Launcher"
        case .code: return "Code Hosting"
        case .translation: return "Translation"
        case .devices: return "Bluetooth"
        case .windows: return "Window Layouts"
        case .files: return "File Actions"
        case .mirror: return "Mirror"
        case .agents: return "AI Coding"
        case .inbox: return "Inbox"
        }
    }
    var icon: String {
        switch self {
        case .home: return "play.circle"
        case .shelf: return "tray"
        case .focus: return "timer"
        case .notes: return "note.text"
        case .dashboard: return "square.grid.2x2"
        case .weather: return "cloud.sun"
        case .health: return "heart"
        case .system: return "gauge.with.dots.needle.50percent"
        case .usage: return "hourglass"
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        case .day: return "sun.horizon"
        case .launcher: return "square.grid.3x3"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .translation: return "character.bubble"
        case .devices: return "headphones"
        case .windows: return "rectangle.split.2x1"
        case .files: return "folder.badge.gearshape"
        case .mirror: return "video"
        case .agents: return "terminal"
        case .inbox: return "bell"
        }
    }
}
struct IslandModulePreferences: Codable,Equatable {
    var order: [NotchViews] = [.dashboard, .home, .shelf, .focus, .notes, .calendar, .tasks, .day, .weather, .health, .system, .usage, .launcher]
    var enabled: [NotchViews] = [.dashboard, .home, .shelf, .focus, .notes]
    var start: NotchViews = .dashboard
    mutating func normalize() {
        var seen = Set<NotchViews>()
        order = (order + NotchViews.allCases).filter { seen.insert($0).inserted }
        enabled = order.filter { enabled.contains($0) }
        if enabled.isEmpty { enabled = [.dashboard] }
        if !enabled.contains(start) { start = enabled[0] }
    }
    mutating func place(_ module:NotchViews,relativeTo target:NotchViews?=nil,after:Bool=false) {
        normalize()
        guard target != module else { return }
        var active=order.filter { enabled.contains($0) && $0 != module }
        let position=target.flatMap { active.firstIndex(of:$0) }.map { $0 + (after ? 1 : 0) } ?? active.count
        active.insert(module,at:position)
        order=active+order.filter { !active.contains($0) }
        enabled=active
        normalize()
    }
}
@MainActor final class IslandModuleStore: ObservableObject {
    static let shared = IslandModuleStore()
    @Published private(set) var preferences = IslandModulePreferences()
    private let defaults: UserDefaults
    var enabled: [NotchViews] { preferences.order.filter { preferences.enabled.contains($0) } }
    var defaultModule: NotchViews { preferences.start }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "island.modules"), let saved = try? JSONDecoder().decode(IslandModulePreferences.self, from: data) { preferences = saved }
        preferences.normalize()
    }
    func setEnabled(_ module: NotchViews, _ enabled: Bool) {
        if enabled { preferences.enabled.append(module) } else { preferences.enabled.removeAll { $0 == module } }
        persist()
    }
    func setDefault(_ module: NotchViews) { preferences.start = module; persist() }
    @discardableResult func place(_ module:NotchViews,relativeTo target:NotchViews?=nil,after:Bool=false)->Bool {
        var next=preferences;next.place(module,relativeTo:target,after:after)
        guard next != preferences else { return false };preferences=next;persist();return true
    }
    func restore(_ snapshot:IslandModulePreferences) { preferences=snapshot;persist() }
    func move(_ module: NotchViews, by delta: Int) {
        guard let index = preferences.order.firstIndex(of: module) else { return }
        let new = min(preferences.order.count - 1, max(0, index + delta)); preferences.order.swapAt(index, new); persist()
    }
    func profile(_ name: String) {
        switch name {
        case "Minimal": preferences.enabled = [.home, .focus]; preferences.start = .home
        case "Work": preferences.enabled = [.dashboard, .focus, .notes, .calendar, .tasks, .day]; preferences.start = .dashboard
        default: preferences.enabled = preferences.order; preferences.start = .dashboard
        }
        persist()
    }
    private func persist() {
        preferences.normalize()
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "island.modules")
        if !enabled.contains(IslandCoordinator.shared.currentView) { IslandCoordinator.shared.currentView = defaultModule }
        IslandUsageTracker.shared.setEnabled(enabled.contains(.usage))
        IslandDevices.shared.configure(IslandModuleStore.shared.enabled.contains(.devices))
        IslandWellbeingReminders.shared.configure(IslandModuleStore.shared.enabled.contains(.health))
        IslandAgentBridge.shared.start(enabled.contains(.agents) || enabled.contains(.inbox))
    }
}
struct IslandModulesSettings: View {
    var body: some View {
        IslandModuleDesigner()
    }
}
struct IslandModuleContent: View {
    let module: NotchViews
    var body: some View {
        ScrollView {
            Group {
                switch module {
                case .weather: IslandWeatherView()
                case .health: IslandHealthView()
                case .system: IslandSystemView()
                case .usage: IslandUsageView()
                case .calendar: IslandAgendaView()
                case .tasks: IslandTasksView()
                case .day: IslandDayView()
                case .launcher: IslandLauncherView()
                case .code: IslandCodeHostingView()
                case .translation: IslandTranslationView()
                case .devices: IslandDevicesView()
                case .windows: IslandWindowSnapView()
                case .files: IslandFileActionsView()
                case .mirror: IslandMirrorView()
                case .agents: IslandAgentView()
                case .inbox: IslandInboxView()
                default: EmptyView()
                }
            }.padding(.horizontal, 12).padding(.vertical, 5)
        }.frame(height: 134)
    }
}
struct IslandModuleHeading: View {
    let title: String
    let subtitle: String
    var body: some View { HStack { Text(title).font(.headline); Spacer(); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
}
