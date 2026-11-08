import SwiftUI
import AppKit

enum IslandActivityRules {
    static func choose(_ available:[IslandCompactKind],rotate:Bool,phase:Int)->IslandCompactKind {
        guard !available.isEmpty else { return .idle }
        return available[rotate ? max(0,phase)%available.count : 0]
    }
    static func excluded(_ bundle:String?,from value:String)->Bool {
        guard let bundle else { return false }
        return value.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.contains(bundle)
    }
}
@MainActor final class IslandLiveActivityClock:ObservableObject {
    static let shared=IslandLiveActivityClock()
    @Published private(set) var phase=0
    private var task:Task<Void,Never>?
    func configure() {
        task?.cancel();task=nil;phase=(phase+1)%100000
        let defaults=UserDefaults.standard
        guard ["island.live.rotate","island.live.calendar","island.live.devices","island.live.notices"].contains(where:{ defaults.bool(forKey:$0) }) else { return }
        task=Task {
            var poll=10
            while !Task.isCancelled {
                if poll>=10 {
                    poll=0;let modules=IslandModuleStore.shared.enabled
                    if defaults.bool(forKey:"island.live.calendar"),(modules.contains(.calendar) || modules.contains(.day)) { await IslandAgenda.shared.refresh() }
                    if defaults.bool(forKey:"island.live.devices"),modules.contains(.devices) { IslandDevices.shared.refresh() }
                }
                try? await Task.sleep(for:.seconds(6));guard !Task.isCancelled else { return };poll+=1;phase=(phase+1)%100000
            }
        }
    }
}
struct IslandLiveActivitySettings:View {
    @AppStorage("island.live.rotate") private var rotate=false
    @AppStorage("island.live.calendar") private var calendar=false
    @AppStorage("island.live.devices") private var devices=false
    @AppStorage("island.live.notices") private var notices=false
    @AppStorage("island.live.timerPriority") private var timerPriority=true
    @AppStorage("island.live.excludedPlayers") private var excluded=""
    private var apps:[NSRunningApplication] { NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }.sorted { ($0.localizedName ?? "")<($1.localizedName ?? "") } }
    var body:some View {
        Form {
            Section("Beside the camera") {
                Toggle("Rotate available activities every 6 seconds",isOn:$rotate)
                Toggle("Keep the focus timer visible while running",isOn:$timerPriority)
                Toggle("Upcoming calendar events",isOn:$calendar)
                Toggle("Connected device batteries",isOn:$devices)
                Toggle("Unread Island Inbox alerts",isOn:$notices)
                Text("Only enabled modules contribute activities. Calendar events appear within 30 minutes of starting. Power notices, system HUDs and pending coding approvals take priority. External displays use the same choices.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Media sources") {
                Text("Hide media activity from selected apps. Playback controls in the Now Playing module remain available.").font(.caption).foregroundStyle(.secondary)
                ForEach(apps,id:\.processIdentifier) { app in
                    if let id=app.bundleIdentifier { Toggle(app.localizedName ?? id,isOn:Binding(get:{ !IslandActivityRules.excluded(id,from:excluded) },set:{ show in var ids=Set(excluded.split(separator:",").map(String.init));if show { ids.remove(id) } else { ids.insert(id) };excluded=ids.sorted().joined(separator:",") })) }
                }
            }
        }.formStyle(.grouped)
        .onChange(of:rotate) { configure() }.onChange(of:calendar) { configure() }.onChange(of:devices) { configure() }.onChange(of:notices) { configure() }.onChange(of:timerPriority) { configure() }.onChange(of:excluded) { configure() }
    }
    private func configure() { IslandLiveActivityClock.shared.configure() }
}
