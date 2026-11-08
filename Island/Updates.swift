import SwiftUI
import Sparkle
import AppKit

// These are Sparkle's own persisted preference keys, shared with its native UI.
enum IslandUpdateRules {
    static func feed(repository:String)->URL? {
        var value=repository.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.hasPrefix("https://github.com/") { value=String(value.dropFirst(19)) }
        if value.hasSuffix(".git") { value=String(value.dropLast(4)) }
        value=value.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        guard value.range(of:"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$",options:.regularExpression) != nil,value.lowercased() != "theboredteam/boring.notch" else { return nil }
        return URL(string:"https://github.com/"+value+"/releases/latest/download/appcast.xml")
    }
    static func canInstall(mode:String,idle:Double,hour:Int,setup:Bool,active:Bool,modal:Bool,timerRunning:Bool,pendingRequests:Bool)->Bool {
        guard mode != "quit",idle.isFinite,idle>=300,!setup,!active,!modal,!timerRunning,!pendingRequests else { return false }
        return mode == "idle" || (mode == "night" && (hour>=22 || hour<7))
    }
}
@MainActor final class IslandUpdates:NSObject,ObservableObject,SPUUpdaterDelegate {
    static let shared=IslandUpdates()
    private(set) var controller:SPUStandardUpdaterController!
    @Published private(set) var message=""
    private var started=false
    private var setupOpen=false
    private var installWhenReady:(()->Void)?
    private var clock:Timer?
    override init() {
        super.init()
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        DispatchQueue.main.async { [weak self] in self?.applyPreferences() }
    }
    func suspendForSetup() { setupOpen=true }
    func resumeAfterSetup() { setupOpen=false;applyPreferences() }
    func applyPreferences() {
        let defaults=UserDefaults.standard
        controller.updater.automaticallyChecksForUpdates=defaults.bool(forKey:"SUEnableAutomaticChecks")
        controller.updater.automaticallyDownloadsUpdates=defaults.bool(forKey:"SUAutomaticallyUpdate")
        let interval=defaults.object(forKey:"SUScheduledCheckInterval") as? Double ?? 86400
        controller.updater.updateCheckInterval=max(3600,interval.isFinite ? interval : 86400)
        guard IslandUpdateConfiguration.isConfigured else { message="Update channel isn’t connected yet. Your choices are saved; Island won’t check until a signed release channel is connected.";return }
        guard !setupOpen,defaults.object(forKey:"firstLaunch") as? Bool == false else { return }
        if !started {
            do { try controller.updater.start();started=true;message="" }
            catch { message="Updates couldn’t start. Review the release channel or try again later." }
        }
        tryInstallWhenReady()
    }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater:SPUUpdater)->Bool { false }
    func feedURLString(for updater:SPUUpdater)->String? { IslandUpdateConfiguration.feedURL?.absoluteString }
    func updater(_ updater:SPUUpdater,mayPerform updateCheck:SPUUpdateCheck) throws {
        if setupOpen || UserDefaults.standard.object(forKey:"firstLaunch") as? Bool != false { throw NSError(domain:"IslandSetup",code:1,userInfo:[NSLocalizedDescriptionKey:"Finish or skip Island setup before checking for updates."]) }
    }
    func updater(_ updater:SPUUpdater,willInstallUpdateOnQuit item:SUAppcastItem,immediateInstallationBlock immediateInstallHandler:@escaping()->Void)->Bool {
        installWhenReady=immediateInstallHandler
        clock?.invalidate()
        clock=Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in self?.tryInstallWhenReady() } }
        message="An update is ready. It will install when you quit Island, or at your chosen idle time."
        tryInstallWhenReady();return true
    }
    private func tryInstallWhenReady() {
        let defaults=UserDefaults.standard
        guard defaults.bool(forKey:"SUEnableAutomaticChecks"),defaults.bool(forKey:"SUAutomaticallyUpdate"),let installWhenReady else { return }
        let idle=CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)
        if IslandUpdateRules.canInstall(mode:defaults.string(forKey:"island.updates.installWhen") ?? "quit",idle:idle,hour:Calendar.current.component(.hour,from:Date()),setup:setupOpen || IslandPermissionSetup.shared.running || IslandPermissionSetup.shared.prompting || IslandPowerController.shared.busy,active:NSApp.isActive,modal:NSApp.modalWindow != nil,timerRunning:IslandFocusTimer.shared.state.deadline != nil || IslandQuickActions.shared.keepingAwake,pendingRequests:!IslandAgentBridge.shared.pending.isEmpty) {
            self.installWhenReady=nil;clock?.invalidate();clock=nil;installWhenReady()
        }
    }
    func connect(repository:String)->Bool {
        guard let feed=IslandUpdateRules.feed(repository:repository) else { message="Enter owner/repository or its GitHub URL.";return false }
        if let bundled=Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String,bundled != feed.absoluteString { message="This release has a fixed update channel. Change the repository in the source before rebuilding.";return false }
        UserDefaults.standard.set(feed.absoluteString,forKey:"island.updates.feed")
        applyPreferences();if started { controller.updater.resetUpdateCycle() };return true
    }
}
struct IslandUpdateOptions:View {
    @AppStorage("SUEnableAutomaticChecks") private var checks=false
    @AppStorage("SUAutomaticallyUpdate") private var automatic=false
    @AppStorage("SUScheduledCheckInterval") private var interval=86400.0
    @AppStorage("island.updates.installWhen") private var installWhen="quit"
    var body:some View {
        Group {
            Toggle("Check for updates automatically",isOn:$checks)
            if checks {
                Picker("Check for new versions",selection:$interval) { Text("Every hour").tag(3600.0);Text("Every day").tag(86400.0);Text("Every week").tag(604800.0) }
                Toggle("Download and install signed updates",isOn:$automatic)
                if automatic {
                    Picker("Install updates",selection:$installWhen) { Text("When I quit Island").tag("quit");Text("After 5 minutes idle, or when I quit").tag("idle");Text("When idle at night (10 PM–7 AM), or when I quit").tag("night") }
                    Text("Idle installs wait while Keep Awake or a focus timer is on, a request needs your response, or you’re using Island. Manual update checks remain available.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !IslandUpdateConfiguration.isConfigured { Label("Release channel not connected. Your choices will apply when it is ready.",systemImage:"info.circle").font(.caption).foregroundStyle(.secondary) }
        }.onChange(of:checks) { IslandUpdates.shared.applyPreferences() }.onChange(of:automatic) { IslandUpdates.shared.applyPreferences() }.onChange(of:interval) { IslandUpdates.shared.applyPreferences() }.onChange(of:installWhen) { IslandUpdates.shared.applyPreferences() }
    }
}
struct IslandUpdatesSettings:View {
    @ObservedObject private var updates=IslandUpdates.shared
    @State private var repository=""
    @State private var error=""
    var body:some View {
        Form {
            Section("Keep Island up to date") { IslandUpdateOptions() }
            Section("This version") {
                LabeledContent("Island",value:Bundle.main.releaseVersionNumber ?? "")
                Label(IslandUpdateConfiguration.isConfigured ? "Signed release channel connected" : "Release channel not connected",systemImage:IslandUpdateConfiguration.isConfigured ? "checkmark.shield" : "link")
                if !updates.message.isEmpty { Text(updates.message).font(.callout).foregroundStyle(.secondary) }
                CheckForUpdatesView(updater:updates.controller.updater).disabled(!IslandUpdateConfiguration.isConfigured)
            }
            Section("For the app owner") {
                DisclosureGroup("Connect a GitHub release repository") {
                    Text("Use the repository where you publish Island’s signed releases. The signing key in this app must match your releases. Connecting here affects this copy; configure the same repository before building the public release.").font(.caption).foregroundStyle(.secondary)
                    TextField("owner/repository",text:$repository).textFieldStyle(.roundedBorder)
                    Button("Connect release channel") { error=updates.connect(repository:repository) ? "" : updates.message }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Link("Create a GitHub repository",destination:URL(string:"https://github.com/new")!)
                    Text("The source download includes START-HERE.md and a release builder. Nothing is published automatically from this page.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
