import SwiftUI
import AppKit
import Combine

struct IslandVisibilityRules {
    static func hidden(bundle:String?,category:String?,hideGames:Bool,excluded:String)->Bool {
        guard let bundle,bundle != "org.islandapp.Island" else { return false }
        let selected=excluded.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        return selected.contains(bundle) || hideGames && (category == "public.app-category.games" || category?.hasSuffix("-games")==true)
    }
}
@MainActor final class IslandVisibility:ObservableObject {
    static let shared=IslandVisibility()
    @Published private(set) var hidden=false
    private var observers:[NSObjectProtocol]=[]
    init() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        refresh()
    }
    func refresh() {
        let app=NSWorkspace.shared.frontmostApplication
        let category=app?.bundleURL.flatMap { Bundle(url:$0)?.object(forInfoDictionaryKey:"LSApplicationCategoryType") as? String }
        let next=IslandVisibilityRules.hidden(bundle:app?.bundleIdentifier,category:category,hideGames:UserDefaults.standard.bool(forKey:"island.visibility.games"),excluded:UserDefaults.standard.string(forKey:"island.visibility.apps") ?? "")
        if hidden != next { hidden=next }
    }
}
struct IslandVisibilitySettings:View {
    @AppStorage("island.visibility.games") private var games=false
    @AppStorage("island.visibility.missionControl") private var missionControl=false
    @AppStorage("island.visibility.apps") private var excluded=""
    @State private var apps:[NSRunningApplication]=[]
    var body:some View {
        Section("Stay out of the way") {
            Toggle("Hide in Mission Control",isOn:$missionControl)
            Toggle("Hide while a game is active",isOn:$games)
            Text("Game detection uses the app’s declared category. Add an app below if its category isn’t supplied. Island returns when you switch apps.").font(.caption).foregroundStyle(.secondary)
            Menu("Hide While Using…") {
                ForEach(apps,id:\.processIdentifier) { app in
                    if let id=app.bundleIdentifier { Button { var values=Set(excluded.split(separator:",").map(String.init));if values.contains(id) { values.remove(id) } else { values.insert(id) };excluded=values.sorted().joined(separator:",") } label:{ Label(app.localizedName ?? id,systemImage:excluded.split(separator:",").contains(Substring(id)) ? "checkmark.circle.fill" : "circle") } }
                }
                Divider();Button("Refresh Running Apps") { refreshApps() }
            }
            ForEach(excluded.split(separator:",").map(String.init).filter { !$0.isEmpty },id:\.self) { id in HStack { Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier:id).flatMap { Bundle(url:$0)?.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String } ?? id).lineLimit(1);Spacer();Button("Remove") { excluded=excluded.split(separator:",").map(String.init).filter { $0 != id }.joined(separator:",") } } }
        }.onAppear { refreshApps() }
    }
    private func refreshApps() { apps=NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "")<($1.localizedName ?? "") } }
}
