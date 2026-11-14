import SwiftUI
import AppKit

enum IslandActivityRules {
    static func choose(_ available:[IslandCompactKind],rotate:Bool,phase:Int,hovered:IslandCompactKind?=nil)->IslandCompactKind {
        guard !available.isEmpty else { return .idle }
        if let hovered,available.contains(hovered) { return hovered }
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
        guard defaults.bool(forKey:"island.live.rotate") || IslandActivityTrayStore.shared.preferences.enabled.contains(.event) || IslandActivityTrayStore.shared.preferences.enabled.contains(.device) else { return }
        task=Task {
            var poll=10
            while !Task.isCancelled {
                if poll>=10 {
                    poll=0;let modules=IslandModuleStore.shared.enabled
                    if IslandActivityTrayStore.shared.preferences.enabled.contains(.event),(modules.contains(.calendar) || modules.contains(.day)) { await IslandAgenda.shared.refresh() }
                    if IslandActivityTrayStore.shared.preferences.enabled.contains(.device),modules.contains(.devices) { IslandDevices.shared.refresh() }
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
    @AppStorage("island.live.excludedPlayers") private var excluded=""
    private var apps:[NSRunningApplication] { NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }.sorted { ($0.localizedName ?? "")<($1.localizedName ?? "") } }
    var body:some View {
        Form {
            Section("Beside the camera") {
                Toggle("Rotate available activities every 6 seconds",isOn:$rotate)
                Button("Choose and arrange activity trays…") { IslandSettingsNavigation.shared.selected="Trays" }
                Text("Add or remove the timer, Wellbeing, AI activity and other trays in Settings → Trays. Their enabled modules supply the activity.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Media sources") {
                Text("Hide media activity from selected apps. Playback controls in the Now Playing module remain available.").font(.caption).foregroundStyle(.secondary)
                ForEach(apps,id:\.processIdentifier) { app in
                    if let id=app.bundleIdentifier { Toggle(app.localizedName ?? id,isOn:Binding(get:{ !IslandActivityRules.excluded(id,from:excluded) },set:{ show in var ids=Set(excluded.split(separator:",").map(String.init));if show { ids.remove(id) } else { ids.insert(id) };excluded=ids.sorted().joined(separator:",") })) }
                }
            }
        }.formStyle(.grouped)
        .onChange(of:rotate) { configure() }.onChange(of:calendar) { configure() }.onChange(of:devices) { configure() }.onChange(of:notices) { configure() }.onChange(of:excluded) { configure() }
    }
    private func configure() { IslandLiveActivityClock.shared.configure() }
}
