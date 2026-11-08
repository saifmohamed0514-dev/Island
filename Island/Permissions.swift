import SwiftUI
import Combine
import AVFoundation
import EventKit
import UserNotifications
import Intents
import Carbon
import CoreGraphics
import ApplicationServices
import OSLog
import CoreBluetooth
import Defaults

enum IslandPermission:String,CaseIterable,Identifiable {
    case accessibility,input,mediaControls,bluetooth,camera,calendar,reminders,notifications,music,spotify,focus,power
    var id:String { rawValue }
    static var visibleCases:[Self] { allCases.filter { $0 != .input } }
    var title:String {
        switch self {
        case .accessibility:return "Window and system controls"
        case .input:return "Media keys"
        case .mediaControls:return "Volume and brightness overlays"
        case .bluetooth:return "Bluetooth devices"
        case .camera:return "Camera"
        case .calendar:return "Calendar"
        case .reminders:return "Reminders"
        case .notifications:return "Notifications"
        case .music:return "Apple Music controls"
        case .spotify:return "Spotify controls"
        case .focus:return "Focus sharing"
        case .power:return "Low Power Mode"
        }
    }
    var detail:String {
        switch self {
        case .accessibility:return "Window layouts and snapping."
        case .input:return "Detect volume and brightness keys for Island’s overlays."
        case .mediaControls:return "Replace the system indicator when you use volume and brightness keys."
        case .bluetooth:return "Connected accessories and the battery levels your Mac shares."
        case .camera:return "Your Mirror preview. Allowing access does not turn the camera on."
        case .calendar:return "Show your upcoming events."
        case .reminders:return "Show, add and complete your tasks."
        case .notifications:return "Wellbeing and low-battery alerts."
        case .music:return "Playback and volume in the Music app. Opens Music during setup."
        case .spotify:return "Playback and volume in Spotify. Opens Spotify during setup."
        case .focus:return "Optional layout changes when your Mac shares its Focus status."
        case .power:return "Change Low Power Mode without a password each time."
        }
    }
    var icon:String {
        switch self {
        case .accessibility:return "macwindow"
        case .input:return "keyboard"
        case .mediaControls:return "slider.horizontal.3"
        case .bluetooth:return "antenna.radiowaves.left.and.right"
        case .camera:return "camera"
        case .calendar:return "calendar"
        case .reminders:return "checklist"
        case .notifications:return "bell"
        case .music,.spotify:return "music.note"
        case .focus:return "moon"
        case .power:return "battery.100"
        }
    }
    var settingsURL:URL {
        let destination:String
        switch self {
        case .camera:destination="com.apple.preference.security?Privacy_Camera"
        case .calendar:destination="com.apple.preference.security?Privacy_Calendars"
        case .reminders:destination="com.apple.preference.security?Privacy_Reminders"
        case .accessibility,.mediaControls:destination="com.apple.preference.security?Privacy_Accessibility"
        case .input:destination="com.apple.preference.security?Privacy_Accessibility"
        case .bluetooth:destination="com.apple.preference.security?Privacy_BluetoothAlways"
        case .notifications:destination="com.apple.Notifications-Settings.extension"
        case .music,.spotify:destination="com.apple.preference.security?Privacy_Automation"
        case .focus:destination="com.apple.Focus-Settings.extension"
        case .power:destination="com.apple.Battery-Settings.extension"
        }
        return URL(string:"x-apple.systempreferences:"+destination)!
    }
    var approvalHelp:String {
        switch self {
        case .accessibility:return "For window layouts and snapping, enable Island under Privacy & Security → Device Control and Data Access (called Accessibility on older macOS versions). Approve the Mac’s Touch ID or password request if it appears."
        case .mediaControls:return "Allow Island to control media-key events. Enable Island in Privacy & Security → Accessibility (called Device Control and Data Access on newer macOS versions). Window access and media-key filtering are checked separately."
        case .input:return IslandPermission.mediaControls.approvalHelp
        case .power:return "Island Power Setup asks for administrator approval once. Approve its own dialog; the ordinary privacy switches can’t enable power controls."
        case .music,.spotify:return "Allow Island to control your player. If you previously declined, enable the player under Island in Privacy & Security → Automation."
        case .notifications:return "Choose Allow in the notification request. If you previously declined, enable Island under Notifications in System Settings."
        case .camera:return "Choose Allow in the Camera request. If you previously declined, enable Island under Privacy & Security → Camera. Access alone never starts your camera."
        case .calendar:return "Allow full Calendar access in the request. If you previously declined, review Island under Privacy & Security → Calendars."
        case .reminders:return "Allow Reminders access in the request. If you previously declined, review Island under Privacy & Security → Reminders."
        case .bluetooth:return "Allow Bluetooth in the request. If you previously declined, review Island under Privacy & Security → Bluetooth."
        case .focus:return "Allow Focus status sharing in the request. If this Mac doesn’t share a status, time-based profiles still work."
        }
    }
    var playerID:String? { self == .music ? "com.apple.Music" : self == .spotify ? "com.spotify.client" : nil }
}
enum IslandPermissionStatus:Equatable {
    case checking,allowed,ask,settings,needsPlayer,restricted,unavailable
    var label:String {
        switch self {
        case .checking:return "Checking…"
        case .allowed:return "Ready"
        case .ask:return "Not set up"
        case .settings:return "Needs approval"
        case .needsPlayer:return "Open player to check"
        case .restricted:return "Restricted by your Mac"
        case .unavailable:return "Unavailable"
        }
    }
    var canSetUp:Bool { self == .ask || self == .settings || self == .needsPlayer }
}
// Recommendations follow the features the user actually chose. These are
// selections only: no permission is requested until Set up selected is pressed.
enum IslandPermissionRecommendations {
    static func selected(modules:[NotchViews],snapping:Bool,hud:Bool,deviceAlerts:Bool,healthAlerts:Bool,player:String,useFocus:Bool)->Set<IslandPermission> {
        var wanted=Set<IslandPermission>()
        if snapping || hud || modules.contains(.windows) { wanted.insert(.accessibility) }
        if hud { wanted.insert(.mediaControls) }
        if modules.contains(.devices) { wanted.insert(.bluetooth) }
        if modules.contains(.mirror) { wanted.insert(.camera) }
        if modules.contains(.calendar) || modules.contains(.day) { wanted.insert(.calendar) }
        if modules.contains(.tasks) { wanted.insert(.reminders) }
        if deviceAlerts || healthAlerts { wanted.insert(.notifications) }
        if player == "appleMusic" { wanted.insert(.music) }
        if player == "spotify" { wanted.insert(.spotify) }
        if useFocus { wanted.insert(.focus) }
        return wanted
    }
}
// Active media-key filtering uses the control grant. A separate passive
// Input Monitoring check can stay false despite that grant and must not block
// an already-authorized filter. The old input key remains a compatibility alias.
struct IslandControlAccess {
    let window:Bool?
    let media:Bool
    var statuses:[IslandPermission:IslandPermissionStatus] {
        [.accessibility:window.map { $0 ? .allowed : .ask } ?? .checking,
         .mediaControls:media ? .allowed : .ask,
         .input:media ? .allowed : .ask]
    }
}
enum IslandPermissionAttempt { case finished,waitingInSettings,waitingForApproval }
@MainActor protocol IslandPermissionClient {
    func snapshot() async -> [IslandPermission:IslandPermissionStatus]
    func controlsSnapshot() async -> [IslandPermission:IslandPermissionStatus]
    func request(_ permission:IslandPermission) async -> IslandPermissionAttempt
}

extension IslandPermissionClient {
    func controlsSnapshot() async -> [IslandPermission:IslandPermissionStatus] { await snapshot() }
}

// A single queue owns requests. Returning from System Settings can resume it;
// cancelling never grants access or starts another native dialog.
@MainActor final class IslandPermissionSetup:ObservableObject {
    @Published private(set) var statuses:[IslandPermission:IslandPermissionStatus]=[:]
    @Published var selected:Set<IslandPermission>=[]
    @Published private(set) var current:IslandPermission?
    @Published private(set) var running=false
    @Published private(set) var prompting=false
    @Published private(set) var waiting=false
    @Published private(set) var waitingInSettings=false
    @Published private(set) var refreshing=false
    @Published private(set) var message=""
    var hasSuggestedSelection=false
    private let client:any IslandPermissionClient
    private var queue:[IslandPermission]=[]
    private var runID=UUID()
    private var revision=0
    private var refreshAgain=false
    private var fullRefreshRequested=false
    private var continueAfterRefresh=false
    private var attempted:Set<IslandPermission>=[]
    private let canPresentNext:()->Bool
    init(client:any IslandPermissionClient,canPresentNext:@escaping()->Bool={ true }) { self.client=client;self.canPresentNext=canPresentNext }
    func status(_ key:IslandPermission)->IslandPermissionStatus { statuses[key] ?? .checking }
    var remaining:[IslandPermission] { IslandPermission.allCases.filter { selected.contains($0) && status($0).canSetUp } }
    var readyCount:Int { selected.filter { status($0) == .allowed }.count }
    func refresh(mayContinue:Bool=true,controlsOnly:Bool=false) async {
        continueAfterRefresh = continueAfterRefresh || mayContinue
        fullRefreshRequested = fullRefreshRequested || !controlsOnly
        if refreshing { refreshAgain=true;return }
        refreshing=true
        repeat {
            refreshAgain=false
            let full=fullRefreshRequested;fullRefreshRequested=false
            let captured=revision
            let values=full ? await client.snapshot() : await client.controlsSnapshot()
            // A poll begun before an approval must never overwrite its result.
            if captured == revision {
                if full { statuses=values } else { statuses.merge(values,uniquingKeysWith:{ _,new in new }) }
            }
        } while refreshAgain
        refreshing=false
        if !running {
            if !selected.isEmpty,readyCount == selected.count { message="All selected features are ready." }
            else if message.hasPrefix("All selected features") || message.hasPrefix("Setup finished.") { updateCompletionMessage() }
        }
        let resume=continueAfterRefresh;continueAfterRefresh=false
        if resume,canPresentNext(),running,waiting,!prompting,let current,status(current) != .checking,!status(current).canSetUp { await advance(id:runID) }
    }
    func begin(_ permissions:[IslandPermission]?=nil) async {
        guard !running,!prompting,!refreshing else { return }
        queue=IslandPermission.allCases.filter { (permissions ?? remaining).contains($0) && status($0).canSetUp }
        guard !queue.isEmpty else { return }
        attempted=Set(queue);runID=UUID();running=true;message="";await advance(id:runID)
    }
    private func advance(id:UUID) async {
        guard running,runID == id,!prompting else { return }
        waiting=false;waitingInSettings=false;current=nil
        while !queue.isEmpty {
            let next=queue.removeFirst()
            guard status(next).canSetUp || status(next) == .checking else { continue }
            current=next;prompting=true;revision+=1
            let result=await client.request(next)
            guard running,runID == id else { prompting=false;message="You can finish setup whenever you’re ready.";return }
            let values=await client.snapshot()
            guard running,runID == id else { prompting=false;return }
            revision+=1;statuses=values;prompting=false
            let state=status(next)
            // Returning from a native API is not proof of access. Wait for the
            // OS snapshot instead of silently declaring this step complete.
            if state == .checking || (state.canSetUp && (result != .finished || state != .settings)) || !canPresentNext() {
                waiting=true;waitingInSettings = result == .waitingInSettings || state == .settings;return
            }
        }
        running=false;current=nil
        updateCompletionMessage()
    }
    private func updateCompletionMessage() {
        let unresolved=attempted.union(selected).filter { status($0) != .allowed }
        message=unresolved.isEmpty ? "All selected features are ready." : "Setup finished. Some features still need access; you can review them below whenever you’re ready."
    }
    func skip() async { guard running,waiting,!prompting else { return };await advance(id:runID) }
    func retry() async {
        guard running,waiting,!prompting,let current else { return }
        queue.insert(current,at:0);await advance(id:runID)
    }
    func stop() {
        revision+=1;runID=UUID();queue=[];running=false;waiting=false;waitingInSettings=false;current=nil
        message=prompting ? "Finish the macOS prompt to continue." : "You can finish setup whenever you’re ready."
    }
}

@MainActor final class IslandSystemPermissionClient:IslandPermissionClient {
    private let store=EKEventStore()
    private let bluetooth=IslandBluetoothConsent()
    private var lastAccessibility:Bool?
    private var lastInput:Bool?
    private var lastStatuses:[IslandPermission:IslandPermissionStatus]=[:]
    private var lastControlReport=""
    private let log=Logger(subsystem:"org.islandapp.Island",category:"Permissions")
    // The main app is sandboxed. Its event-filter grant is queried through
    // CoreGraphics; AX window reads belong exclusively to the window helper.
    nonisolated static func mainAccessibilityAuthorized()->Bool {
        CGPreflightPostEventAccess()
    }
    static func automationStatus(_ id:String,ask:Bool=false) async -> IslandPermissionStatus {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) != nil else { return .unavailable }
        // A non-running player cannot answer Automation checks reliably.
        if !ask,NSRunningApplication.runningApplications(withBundleIdentifier:id).isEmpty { return .needsPlayer }
        return await Task.detached { () -> IslandPermissionStatus in
            let target=NSAppleEventDescriptor(bundleIdentifier:id)
            switch AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,ask) {
            case OSStatus(noErr):return .allowed
            case OSStatus(errAEEventNotPermitted):return .settings
            case OSStatus(errAEEventWouldRequireUserConsent):return .ask
            case OSStatus(procNotFound):return .needsPlayer
            default:return .unavailable
            }
        }.value
    }
    func snapshot() async -> [IslandPermission:IslandPermissionStatus] {
        // Start independent remote checks together; one slow helper must not
        // serially delay every other permission.
        async let controlsCheck=controlsSnapshot()
        async let powerCheck=IslandPowerController.shared.checkAvailability()
        async let musicCheck=Self.automationStatus("com.apple.Music")
        async let spotifyCheck=Self.automationStatus("com.spotify.client")
        async let alertsCheck=UNUserNotificationCenter.current().notificationSettings()
        var result:[IslandPermission:IslandPermissionStatus]=[:]
        switch CBManager.authorization {
        case .allowedAlways:result[.bluetooth] = .allowed
        case .notDetermined:result[.bluetooth] = .ask
        case .denied:result[.bluetooth] = .settings
        default:result[.bluetooth] = .restricted
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:result[.camera] = .allowed
        case .notDetermined:result[.camera] = .ask
        case .denied:result[.camera] = .settings
        default:result[.camera] = .restricted
        }
        for (key,entity) in [(IslandPermission.calendar,EKEntityType.event),(.reminders,.reminder)] {
            switch EKEventStore.authorizationStatus(for:entity) {
            case .fullAccess:result[key] = .allowed
            case .notDetermined,.writeOnly:result[key] = .ask
            case .denied:result[key] = .settings
            default:result[key] = .restricted
            }
        }
        let alerts=await alertsCheck
        switch alerts.authorizationStatus {
        case .authorized,.provisional:result[.notifications] = .allowed
        case .notDetermined:result[.notifications] = .ask
        case .denied:result[.notifications] = .settings
        default:result[.notifications] = .unavailable
        }
        result.merge(await controlsCheck,uniquingKeysWith:{ _,new in new })
        result[.power] = await powerCheck ? .allowed : .ask
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized:result[.focus] = INFocusStatusCenter.default.focusStatus.isFocused == nil ? .unavailable : .allowed
        case .notDetermined:result[.focus] = .ask
        case .denied:result[.focus] = .settings
        default:result[.focus] = .restricted
        }
        result[.music] = await musicCheck
        result[.spotify] = await spotifyCheck
        let changed=Set(result.keys.filter { result[$0] != .checking && result[$0] != lastStatuses[$0] })
        lastStatuses=result
        if changed.contains(.camera) { WebcamManager.shared.refreshAuthorization() }
        if changed.contains(.calendar) || changed.contains(.reminders) { Task { await IslandAgenda.shared.refresh() } }
        if changed.contains(.bluetooth) { IslandDevices.shared.refresh() }
        return result
    }
    func controlsSnapshot() async -> [IslandPermission:IslandPermissionStatus] {
        let helperAccess=await XPCHelperClient.shared.accessibilityAuthorizationStatus(),mainAccess=Self.mainAccessibilityAuthorized()
        let result=IslandControlAccess(window:helperAccess,media:mainAccess).statuses
        let accessibility=result[.accessibility] == .allowed
        let report="mediaControl=\(mainAccess) windowHelper=\(helperAccess.map(String.init) ?? "checking")"
        if report != lastControlReport { log.notice("System access: \(report,privacy:.public)");lastControlReport=report }
        if helperAccess != nil {
            if lastAccessibility != accessibility { IslandWindowSnapping.shared.configure() }
            lastAccessibility=accessibility
        }
        let mediaReady=mainAccess
        if mediaReady { await MediaKeyInterceptor.shared.start(promptIfNeeded:false) }
        else if lastInput != mediaReady { MediaKeyInterceptor.shared.stop() }
        lastInput=mediaReady
        return result
    }
    static func openSettings(_ key:IslandPermission) {
        if !NSWorkspace.shared.open(key.settingsURL) { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!) }
    }
    func request(_ key:IslandPermission) async -> IslandPermissionAttempt {
        let current=await snapshot()[key] ?? .unavailable
        guard current.canSetUp else { return .finished }
        // A denied privacy grant can only be changed manually. Explain that in
        // Island; opening Settings is a separate, explicit user action.
        if current == .settings { return .waitingInSettings }
        NSApp.activate(ignoringOtherApps:true)
        switch key {
        case .bluetooth:await bluetooth.request()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for:.video)
            WebcamManager.shared.refreshAuthorization()
        case .calendar,.reminders:
            do {
                if key == .calendar { _ = try await store.requestFullAccessToEvents() }
                else { _ = try await store.requestFullAccessToReminders() }
            } catch { }
            Task { await IslandAgenda.shared.refresh() }
        case .notifications:_ = await IslandNotices.shared.requestPermission()
        case .accessibility:
            XPCHelperClient.shared.requestAccessibilityAuthorization()
            return .waitingForApproval
        case .mediaControls,.input:
            _ = CGRequestPostEventAccess()
            return .waitingForApproval
        case .power:
            IslandPowerController.shared.install();return .waitingForApproval
        case .focus:
            await withCheckedContinuation { continuation in INFocusStatusCenter.default.requestAuthorization { _ in continuation.resume() } }
        case .music,.spotify:
            guard let id=key.playerID,let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) else { return .finished }
            if NSRunningApplication.runningApplications(withBundleIdentifier:id).isEmpty {
                let config=NSWorkspace.OpenConfiguration();config.activates=true
                let opened:Bool=await withCheckedContinuation { continuation in NSWorkspace.shared.openApplication(at:url,configuration:config) { app,_ in continuation.resume(returning:app != nil) } }
                guard opened else { return .finished }
            }
            _ = await Self.automationStatus(id,ask:true)
        }
        return .finished
    }
}

@MainActor private final class IslandBluetoothConsent:NSObject,CBCentralManagerDelegate {
    private var manager:CBCentralManager?
    private var continuation:CheckedContinuation<Void,Never>?
    func request() async {
        guard CBManager.authorization == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            self.continuation=continuation
            manager=CBCentralManager(delegate:self,queue:.main,options:[CBCentralManagerOptionShowPowerAlertKey:false])
        }
    }
    nonisolated func centralManagerDidUpdateState(_ central:CBCentralManager) {
        Task { @MainActor in
            guard CBManager.authorization != .notDetermined else { return }
            continuation?.resume();continuation=nil;manager=nil
        }
    }
}

@MainActor extension IslandPermissionSetup {
    static let shared=IslandPermissionSetup(client:IslandSystemPermissionClient(),canPresentNext:{ NSApp.isActive })
}
@MainActor final class IslandPermissionMonitor {
    static let shared=IslandPermissionMonitor()
    private var observer:NSObjectProtocol?
    private var task:Task<Void,Never>?
    func start() {
        guard task == nil else { return }
        observer=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { _ in
            Task { @MainActor in await IslandPermissionSetup.shared.refresh(mayContinue:NSApp.isActive) }
        }
        task=Task { @MainActor in
            while !Task.isCancelled {
                let setup=IslandPermissionSetup.shared
                await setup.refresh(mayContinue:NSApp.isActive,controlsOnly:!setup.running)
                let frequent=Defaults[.hudReplacement] || UserDefaults.standard.bool(forKey:"island.windows.snap") || IslandPermissionSetup.shared.running
                do { try await Task.sleep(for:.seconds(frequent ? 3 : 30)) } catch { return }
            }
        }
    }
}

struct IslandPermissionsView:View {
    var guidedSetup=false
    @State private var showAll=false
    @State private var recommendations=Set<IslandPermission>()
    private var visiblePermissions:[IslandPermission] { IslandPermission.visibleCases.filter { !guidedSetup || showAll || recommendations.contains($0) || setup.selected.contains($0) } }
    @ObservedObject private var setup=IslandPermissionSetup.shared
    @ObservedObject private var power=IslandPowerController.shared
    @ObservedObject private var bridge=IslandAgentBridge.shared
    @ObservedObject private var navigation=IslandSettingsNavigation.shared
    var body:some View {
        ScrollViewReader { scroll in
        Form {
            Section {
                Label(guidedSetup ? "Access for your Island" : "A little setup. Then you’re ready.",systemImage:"checkmark.shield").font(.title2.weight(.semibold))
                Text(guidedSetup ? "These permissions support the features you chose. Set them up now, or continue and finish later. Approvals happen one at a time." : "Choose the features you want. Island will guide you through one approval at a time and skip anything already allowed.").foregroundStyle(.secondary)
                HStack {
                    Button("Set up selected") { Task { await setup.begin() } }.buttonStyle(.borderedProminent).disabled(setup.running || setup.prompting || setup.refreshing || setup.remaining.isEmpty)
                    if !guidedSetup || showAll { Button("Select all") { setup.selected=Set(IslandPermission.visibleCases.filter { setup.status($0).canSetUp }) }.disabled(setup.running || setup.prompting) }
                    Button("Clear selection") { setup.selected=[] }.disabled(setup.running || setup.prompting)
                    Spacer()
                    Button("Check access",systemImage:"arrow.clockwise") { Task { await setup.refresh(mayContinue:NSApp.isActive) } }.accessibilityLabel("Refresh all permission statuses").disabled(setup.refreshing || setup.prompting)
                }
                if setup.refreshing { HStack { ProgressView().controlSize(.mini);Text("Checking access on this Mac…").font(.caption).foregroundStyle(.secondary) } }
                else { Text("\(setup.readyCount) of \(setup.selected.count) selected features ready. Access refreshes automatically when you return to Island.").font(.caption).foregroundStyle(.secondary) }
                Text("macOS keeps approvals separate. It may use Touch ID or your login password for administrator changes; privacy prompts have their own Allow buttons.").font(.caption).foregroundStyle(.secondary)
            }.id("permission-progress")
            if let current=setup.current {
                Section("Setting up "+current.title) {
                    if setup.waiting {
                        if setup.status(current) == .allowed { Label("Access confirmed. Return to Island to continue.",systemImage:"checkmark.circle.fill").foregroundStyle(.green) }
                        else { Text(setup.waitingInSettings ? "macOS requires you to change this access in System Settings. Open it when you’re ready, enable access, then return to Island." : "Follow the macOS approval prompt. Island will keep this step open and won’t switch apps for you.") }
                        Text(current.approvalHelp).font(.callout).foregroundStyle(.secondary)
                        if current == .power,!power.message.isEmpty { Text(power.message).font(.caption).foregroundStyle(.secondary) }
                        if current != .power { Button("Open System Settings…") { IslandSystemPermissionClient.openSettings(current) } }
                        HStack {
                            Button("Check access") { Task { await setup.refresh(mayContinue:NSApp.isActive) } }.accessibilityLabel("Check access for "+current.title)
                            if !setup.waitingInSettings { Button("Show prompt again") { Task { await setup.retry() } }.disabled(current == .power && power.busy) }
                            Button("Skip for now") { Task { await setup.skip() } }
                        }
                        if current == .input || current == .accessibility || current == .mediaControls {
                            Text("Already enabled in System Settings? macOS may need Island to reopen before the new access takes effect. Your settings will be kept.").font(.caption).foregroundStyle(.secondary)
                            Button("Restart Island…") { ApplicationRelauncher.restart(showPermissions:true) }.disabled(setup.prompting)
                        }
                    } else { HStack { ProgressView().controlSize(.small);Text("Follow the macOS prompt.") } }
                    Button("Finish later") { setup.stop() }
                }
            }
            if !setup.message.isEmpty { Section { Text(setup.message).foregroundStyle(.secondary) } }
            Section(guidedSetup ? "For the features you chose" : "Your features") {
                if visiblePermissions.isEmpty { Label("No extra access is needed for your current choices. Continue whenever you’re ready.",systemImage:"checkmark.circle").foregroundStyle(.secondary) }
                ForEach(visiblePermissions) { key in permissionRow(key) }
                if guidedSetup { Button(showAll ? "Show recommended permissions" : "Show other permissions") { showAll.toggle() }.disabled(setup.running || setup.prompting) }
            }
            Section("Files and app connections") {
                Text("Files and folders are approved when you choose them. Island doesn’t need access to your whole disk, microphone or screen recording to use these features.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("ChatGPT, Claude and Cursor",value:bridge.events.isEmpty ? (bridge.folderName == nil ? "Not connected" : "Folder connected") : "Activity received")
                Text("Hook review stays in the connected app. A connected folder does not mean its hooks have been trusted.").font(.caption).foregroundStyle(.secondary)
                Button("Manage app connections") { IslandSettingsNavigation.shared.selected="Agents & Inbox" }
            }
        }.formStyle(.grouped)
        .task {
            recommendations=IslandPermissionRecommendations.selected(
                    modules:IslandModuleStore.shared.enabled,
                    snapping:UserDefaults.standard.bool(forKey:"island.windows.snap"),hud:Defaults[.hudReplacement],
                    deviceAlerts:UserDefaults.standard.bool(forKey:"island.devices.alerts"),healthAlerts:UserDefaults.standard.bool(forKey:"island.health.reminders"),
                    player:Defaults[.mediaController] == .appleMusic ? "appleMusic" : Defaults[.mediaController] == .spotify ? "spotify" : "nowPlaying",
                    useFocus:UserDefaults.standard.bool(forKey:"island.schedule.useFocus"))
            if !setup.hasSuggestedSelection { setup.selected=recommendations;setup.hasSuggestedSelection=true }
            if let requested=navigation.requestedPermission,!guidedSetup {
                setup.selected.insert(requested)
                if Defaults[.hudReplacement],requested == .accessibility || requested == .input || requested == .mediaControls { setup.selected.formUnion([.accessibility,.mediaControls]) }
            }
            await setup.refresh(mayContinue:NSApp.isActive)
            while !Task.isCancelled { do { try await Task.sleep(for:.seconds(setup.running ? 1 : 5)) } catch { return };await setup.refresh(mayContinue:NSApp.isActive) }
        }.onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in Task { await setup.refresh(mayContinue:true) } }.onChange(of:navigation.requestedPermission) { if let key=navigation.requestedPermission { setup.selected.insert(key) } }
        .onChange(of:setup.current) { if setup.current != nil { withAnimation(.easeInOut(duration:0.18)) { scroll.scrollTo("permission-progress",anchor:.top) } } }
        .onDisappear { setup.stop() }
        }
    }
    private func permissionRow(_ key:IslandPermission)->some View {
        let state=setup.status(key)
        return HStack(alignment:.top,spacing:12) {
            Toggle(key.title,isOn:Binding(get:{ state == .allowed || setup.selected.contains(key) },set:{ if $0 { setup.selected.insert(key) } else { setup.selected.remove(key) } })).labelsHidden().toggleStyle(.checkbox).disabled(!state.canSetUp || setup.running)
            Image(systemName:key.icon).frame(width:20).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:4) { Text(key.title).fontWeight(.medium);Text(key.detail).font(.caption).foregroundStyle(.secondary);Label(state.label,systemImage:state == .allowed ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(state == .allowed ? .green : .secondary) }
            Spacer(minLength:8)
            if state.canSetUp { Button(state == .settings ? "Review…" : "Set up") { Task { await setup.begin([key]) } }.accessibilityLabel((state == .settings ? "Review " : "Set up ")+key.title).disabled(setup.running || setup.prompting || setup.refreshing) }
            else if state == .allowed { Button("Manage…") { IslandSystemPermissionClient.openSettings(key) }.accessibilityLabel("Manage "+key.title+" access").disabled(setup.running || setup.prompting) }
        }.padding(.vertical,6).accessibilityElement(children:.contain)
    }
}
