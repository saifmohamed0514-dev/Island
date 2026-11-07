import SwiftUI
import Combine
import Intents

enum IslandWidget:String,CaseIterable,Identifiable {
    case clock,focus,music,notes,battery,day,files
    var id:String { rawValue }
    var title:String { switch self { case .clock:return "Clock";case .focus:return "Focus";case .music:return "Now Playing";case .notes:return "Notes";case .battery:return "Battery";case .day:return "Day Progress";case .files:return "File Tray" } }
    var icon:String { switch self { case .clock:return "clock";case .focus:return "timer";case .music:return "music.note";case .notes:return "note.text";case .battery:return "battery.100";case .day:return "sun.horizon";case .files:return "tray" } }
    var module:NotchViews? { switch self { case .focus:return .focus;case .music:return .home;case .notes:return .notes;case .files:return .shelf;default:return nil } }
    static func slots(_ raw:String)->[IslandWidget] {
        let parsed = raw.split(separator:",").compactMap { IslandWidget(rawValue:String($0)) }
        return Array((parsed + [.clock,.focus,.music,.notes]).prefix(4))
    }
}
enum IslandScheduleRules {
    static func profile(minute:Int,start:Int,end:Int)->String {
        let m = min(1439,max(0,minute)), s = min(1439,max(0,start)), e = min(1439,max(0,end))
        guard s != e else { return "Minimal" }
        let active = s < e ? m >= s && m < e : m >= s || m < e
        return active ? "Work" : "Minimal"
    }
}
@MainActor final class IslandProfileSchedule {
    static let shared = IslandProfileSchedule()
    private var task:Task<Void,Never>?
    private var applied:String?
    func start() {
        task?.cancel(); task = nil
        guard UserDefaults.standard.bool(forKey:"island.schedule.enabled") || UserDefaults.standard.bool(forKey:"island.schedule.useFocus") else { applied = nil; return }
        task = Task { [weak self] in
            while !Task.isCancelled { self?.check(); try? await Task.sleep(for:.seconds(30)) }
        }
    }
    private func check() {
        let defaults = UserDefaults.standard, components = Calendar.current.dateComponents([.hour,.minute,.day,.month,.year],from:Date())
        let start = defaults.object(forKey:"island.schedule.start") as? Int ?? 540
        let end = defaults.object(forKey:"island.schedule.end") as? Int ?? 1020
        let timed = IslandScheduleRules.profile(minute:(components.hour ?? 0)*60+(components.minute ?? 0),start:start,end:end)
        let focus=INFocusStatusCenter.default.authorizationStatus == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
        let useFocus=defaults.bool(forKey:"island.schedule.useFocus") && focus != nil
        let profile=useFocus ? (focus == true ? "Work" : "Minimal") : timed
        if !useFocus && !defaults.bool(forKey:"island.schedule.enabled") { return }
        let stamp = "\(useFocus)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(start)-\(end)-\(profile)"
        guard stamp != applied else { return }; applied = stamp
        IslandModuleStore.shared.profile(profile)
    }
}
struct IslandDashboardSettings:View {
    @AppStorage("island.dashboard.slots") var slots = "clock,focus,music,notes"
    @AppStorage("island.schedule.enabled") var scheduled = false
    @AppStorage("island.schedule.useFocus") var useFocus=false
    @State var focusStatus=""
    @AppStorage("island.schedule.start") var start = 540
    @AppStorage("island.schedule.end") var end = 1020
    func time(_ value:Binding<Int>)->Binding<Date> {
        Binding(get:{ Calendar.current.date(bySettingHour:value.wrappedValue/60,minute:value.wrappedValue%60,second:0,of:Date()) ?? Date() },set:{ date in let c=Calendar.current.dateComponents([.hour,.minute],from:date);value.wrappedValue=(c.hour ?? 0)*60+(c.minute ?? 0) })
    }
    var body:some View {
        Form {
            Section("Classic Dashboard widgets") {
                ForEach(0..<4,id:\.self) { index in
                    Picker("Widget \(index+1)",selection:Binding(get:{ IslandWidget.slots(slots)[index] },set:{ new in var widgets=IslandWidget.slots(slots);widgets[index]=new;slots=widgets.map(\.rawValue).joined(separator:",") })) { ForEach(IslandWidget.allCases) { Text($0.title).tag($0) } }
                }
                Text("Widgets open their module when it is enabled. Your widget choices stay the same when you change layouts.").foregroundStyle(.secondary)
                Text("Arrange full module blocks in Settings → Modules. These classic widgets are also available by adding Dashboard as a block.").font(.caption).foregroundStyle(.secondary)
            }
            Section("System Focus") {
                Toggle("Follow shared Focus status",isOn:$useFocus)
                Text("Applies Work while a shared system Focus is on and Minimal when it is off. Requires Focus sharing permission. Focus takes priority over the daily schedule; macOS shares an on/off state, not the Focus name.").font(.caption).foregroundStyle(.secondary)
                if !focusStatus.isEmpty { Text(focusStatus).foregroundStyle(.secondary) }
            }
            Section("Daily layout schedule") {
                Toggle("Switch module layouts on a schedule",isOn:$scheduled)
                DatePicker("Work starts",selection:time($start),displayedComponents:.hourAndMinute).disabled(!scheduled)
                DatePicker("Minimal starts",selection:time($end),displayedComponents:.hourAndMinute).disabled(!scheduled)
                Text("Applies Work at the first time and Minimal at the second, every day in your Mac’s time zone. Turning this on applies the current layout immediately. Manual changes last until the next boundary; your notes, files and timer are kept.").font(.caption).foregroundStyle(.secondary)
                if start == end { Text("Choose different times to schedule a Work period.").foregroundStyle(.orange) }
            }
        }.formStyle(.grouped).onChange(of:useFocus) {
            if useFocus && INFocusStatusCenter.default.authorizationStatus != .authorized { useFocus=false;IslandSettingsController.shared.showPermissions(.focus) }
            else if useFocus && INFocusStatusCenter.default.focusStatus.isFocused == nil { useFocus=false;focusStatus="Focus sharing is unavailable for Island on this Mac. Use the daily schedule instead." }
            IslandProfileSchedule.shared.start()
        }.onChange(of:scheduled) { IslandProfileSchedule.shared.start() }.onChange(of:start) { IslandProfileSchedule.shared.start() }.onChange(of:end) { IslandProfileSchedule.shared.start() }
    }
}
struct IslandDashboardView:View {
    @AppStorage("island.dashboard.slots") var slots = "clock,focus,music,notes"
    @ObservedObject var timer = IslandFocusTimer.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @ObservedObject var modules = IslandModuleStore.shared
    @ObservedObject var coordinator = IslandCoordinator.shared
    var body:some View {
        TimelineView(.periodic(from:.now,by:1)) { context in
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(Array(IslandWidget.slots(slots).enumerated()),id:\.offset) { _,widget in
                    Button { if let module=widget.module, modules.enabled.contains(module) { coordinator.currentView=module } } label: {
                        HStack(spacing:12) {
                            Image(systemName:widget.icon).foregroundStyle(.cyan).font(.system(size:19)).frame(width:28)
                            VStack(alignment:.leading,spacing:4) { Text(widget.title).font(.caption).foregroundStyle(.secondary); Text(value(widget,at:context.date)).font(.system(size:16,weight:.medium,design:.rounded)).lineLimit(1).monospacedDigit() }
                            Spacer(minLength:0)
                            if let module=widget.module, modules.enabled.contains(module) { Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.horizontal,14).frame(height:62).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain).accessibilityLabel(widget.title+", "+value(widget,at:context.date))
                }
            }
        }
    }
    func value(_ widget:IslandWidget,at date:Date)->String {
        switch widget {
        case .clock:return date.formatted(date:.omitted,time:.shortened)
        case .focus:return timer.state.deadline != nil || (!timer.state.finished && timer.state.remaining < timer.state.duration) ? timer.label : "Ready when you are"
        case .music:return music.isPlayerIdle ? "Not Playing" : music.songTitle
        case .notes:return "Capture a thought"
        case .files:return "Drop something here"
        case .battery:return "\(islandBatteryPercent(battery.levelBattery))%"+(battery.isCharging ? " · Charging" : "")
        case .day:
            let beginning=Calendar.current.startOfDay(for:date), end=Calendar.current.date(byAdding:.day,value:1,to:beginning) ?? beginning.addingTimeInterval(86400)
            return "\(Int(min(100,max(0,date.timeIntervalSince(beginning)/end.timeIntervalSince(beginning)*100))))% of today"
        }
    }
}
