import SwiftUI
import Combine
import AVFoundation
import EventKit
import UserNotifications
import Intents
import Carbon
import CoreGraphics
import CoreBluetooth
import Defaults

enum IslandPermission:String,CaseIterable,Identifiable {
    case accessibility,input,bluetooth,camera,calendar,reminders,notifications,music,spotify,focus,power
    var id:String { rawValue }
    var title:String {
        switch self {
        case .accessibility:return "Window and system controls"
        case .input:return "Media keys"
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
        case .accessibility:return "Window layouts, snapping, and volume and brightness overlays."
        case .input:return "Detect volume and brightness keys for Island’s overlays."
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
        case .accessibility:destination="com.apple.preference.security?Privacy_Accessibility"
        case .input:destination="com.apple.preference.security?Privacy_ListenEvent"
        case .bluetooth:destination="com.apple.preference.security?Privacy_BluetoothAlways"
        case .notifications:destination="com.apple.Notifications-Settings.extension"
        case .music,.spotify:destination="com.apple.preference.security?Privacy_Automation"
        case .focus:destination="com.apple.Focus-Settings.extension"
        case .power:destination="com.apple.Battery-Settings.extension"
        }
        return URL(string:"x-apple.systempreferences:"+destination)!
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
enum IslandPermissionAttempt { case finished,waitingInSettings }
@MainActor protocol IslandPermissionClient {
    func snapshot() async -> [IslandPermission:IslandPermissionStatus]
    func request(_ permission:IslandPermission) async -> IslandPermissionAttempt
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
    @Published private(set) var refreshing=false
    @Published private(set) var message=""
    var hasSuggestedSelection=false
    private let client:any IslandPermissionClient
    private var queue:[IslandPermission]=[]
    private var runID=UUID()
    init(client:any IslandPermissionClient) { self.client=client }
    func status(_ key:IslandPermission)->IslandPermissionStatus { statuses[key] ?? .checking }
    var remaining:[IslandPermission] { IslandPermission.allCases.filter { selected.contains($0) && status($0).canSetUp } }
    func refresh() async {
        guard !refreshing else { return };refreshing=true
        statuses=await client.snapshot();refreshing=false
        if running,waiting,!prompting,let current,status(current) != .checking,!status(current).canSetUp { await advance(id:runID) }
    }
    func begin(_ permissions:[IslandPermission]?=nil) async {
        guard !running,!prompting,!refreshing else { return }
        queue=(permissions ?? remaining).filter { status($0).canSetUp }
        guard !queue.isEmpty else { return }
        runID=UUID();running=true;message="";await advance(id:runID)
    }
    private func advance(id:UUID) async {
        guard running,runID == id,!prompting else { return }
        waiting=false;current=nil
        while !queue.isEmpty {
            let next=queue.removeFirst()
            guard status(next).canSetUp else { continue }
            current=next;prompting=true
            let result=await client.request(next)
            prompting=false
            guard running,runID == id else { message="You can finish setup whenever you’re ready.";return }
            statuses=await client.snapshot()
            guard running,runID == id else { return }
            if result == .waitingInSettings,status(next) != .allowed { waiting=true;return }
        }
        running=false;current=nil
        message="Setup finished. Anything you skipped can be set up here later."
    }
    func skip() async { guard running,waiting,!prompting else { return };await advance(id:runID) }
    func retry() async {
        guard running,waiting,!prompting,let current else { return }
        queue.insert(current,at:0);await advance(id:runID)
    }
    func stop() {
        runID=UUID();queue=[];running=false;waiting=false;current=nil
        message=prompting ? "Finish the macOS prompt to continue." : "You can finish setup whenever you’re ready."
    }
}

@MainActor final class IslandSystemPermissionClient:IslandPermissionClient {
    private let store=EKEventStore()
    private let bluetooth=IslandBluetoothConsent()
    private var lastAccessibility:Bool?
    private var lastInput:Bool?
    static func automationStatus(_ id:String,ask:Bool=false) async -> IslandPermissionStatus {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) != nil else { return .unavailable }
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
        let alerts=await UNUserNotificationCenter.current().notificationSettings()
        switch alerts.authorizationStatus {
        case .authorized,.provisional:result[.notifications] = .allowed
        case .notDetermined:result[.notifications] = .ask
        case .denied:result[.notifications] = .settings
        default:result[.notifications] = .unavailable
        }
        let accessibility=await XPCHelperClient.shared.isAccessibilityAuthorized(),input=CGPreflightListenEventAccess()
        result[.accessibility] = accessibility ? .allowed : .ask
        result[.input] = input ? .allowed : .ask
        if accessibility && lastAccessibility != accessibility { IslandWindowSnapping.shared.configure() }
        if accessibility && (lastAccessibility != accessibility || lastInput != input) { await MediaKeyInterceptor.shared.start(promptIfNeeded:false) }
        lastAccessibility=accessibility;lastInput=input
        result[.power] = await IslandPowerController.shared.checkAvailability() ? .allowed : .ask
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized:result[.focus] = INFocusStatusCenter.default.focusStatus.isFocused == nil ? .unavailable : .allowed
        case .notDetermined:result[.focus] = .ask
        case .denied:result[.focus] = .settings
        default:result[.focus] = .restricted
        }
        result[.music] = await Self.automationStatus("com.apple.Music")
        result[.spotify] = await Self.automationStatus("com.spotify.client")
        return result
    }
    static func openSettings(_ key:IslandPermission) {
        if !NSWorkspace.shared.open(key.settingsURL) { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!) }
    }
    func request(_ key:IslandPermission) async -> IslandPermissionAttempt {
        let current=await snapshot()[key] ?? .unavailable
        guard current.canSetUp else { return .finished }
        if current == .settings { Self.openSettings(key);return .waitingInSettings }
        NSApp.activate(ignoringOtherApps:true)
        switch key {
        case .bluetooth:await bluetooth.request()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for:.video)
            WebcamManager.shared.checkAndRequestVideoAuthorization()
        case .calendar,.reminders:
            do {
                if key == .calendar { _ = try await store.requestFullAccessToEvents() }
                else { _ = try await store.requestFullAccessToReminders() }
            } catch { }
            await IslandAgenda.shared.refresh()
        case .notifications:_ = await IslandNotices.shared.requestPermission()
        case .accessibility:
            if !(await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded:true)) { Self.openSettings(key);return .waitingInSettings }
        case .input:
            if !CGRequestListenEventAccess() { Self.openSettings(key);return .waitingInSettings }
        case .power:
            IslandPowerController.shared.install();return .waitingInSettings
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
    static let shared=IslandPermissionSetup(client:IslandSystemPermissionClient())
}
struct IslandPermissionsView:View {
    @ObservedObject private var setup=IslandPermissionSetup.shared
    @ObservedObject private var power=IslandPowerController.shared
    @ObservedObject private var bridge=IslandAgentBridge.shared
    @ObservedObject private var navigation=IslandSettingsNavigation.shared
    var body:some View {
        ScrollViewReader { scroll in
        Form {
            Section {
                Label("A little setup. Then you’re ready.",systemImage:"checkmark.shield").font(.title2.weight(.semibold))
                Text("Choose the features you want. Island will guide you through one approval at a time and skip anything already allowed.").foregroundStyle(.secondary)
                HStack {
                    Button("Set up selected") { Task { await setup.begin() } }.buttonStyle(.borderedProminent).disabled(setup.running || setup.prompting || setup.refreshing || setup.remaining.isEmpty)
                    Button("Select all") { setup.selected=Set(IslandPermission.allCases.filter { setup.status($0).canSetUp }) }.disabled(setup.running || setup.prompting)
                    Button("Clear selection") { setup.selected=[] }.disabled(setup.running || setup.prompting)
                }
                Text("macOS keeps approvals separate. It may use Touch ID or your login password for administrator changes; privacy prompts have their own Allow buttons.").font(.caption).foregroundStyle(.secondary)
            }.id("permission-progress")
            if let current=setup.current {
                Section("Setting up "+current.title) {
                    if setup.waiting {
                        Text(current == .power ? "Approve Island Power Setup if your Mac asks. This page will continue when the controls are ready." : "Allow Island’s access in System Settings, then return here. This page checks automatically.")
                        if current == .power,!power.message.isEmpty { Text(power.message).font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Check again") { Task { await setup.refresh() } };Button("Try again") { Task { await setup.retry() } }.disabled(current == .power && power.busy);Button("Not now") { Task { await setup.skip() } } }
                    } else { HStack { ProgressView().controlSize(.small);Text("Follow the macOS prompt.") } }
                    Button("Finish later") { setup.stop() }
                }
            }
            if !setup.message.isEmpty { Section { Text(setup.message).foregroundStyle(.secondary) } }
            Section("Your features") {
                ForEach(IslandPermission.allCases) { key in permissionRow(key) }
            }
            Section("Files and app connections") {
                Text("Files and folders are approved when you choose them. Island doesn’t need access to your whole disk, microphone or screen recording to use these features.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("ChatGPT, Claude and Cursor",value:bridge.events.isEmpty ? (bridge.folderName == nil ? "Not connected" : "Folder connected") : "Activity received")
                Text("Hook review stays in the connected app. A connected folder does not mean its hooks have been trusted.").font(.caption).foregroundStyle(.secondary)
                Button("Manage app connections") { IslandSettingsNavigation.shared.selected="Agents & Inbox" }
            }
        }.formStyle(.grouped)
        .task {
            await setup.refresh()
            if !setup.hasSuggestedSelection {
                let modules=IslandModuleStore.shared.enabled
                var wanted:Set<IslandPermission>=[.power]
                if Defaults[.hudReplacement] || modules.contains(.windows) { wanted.insert(.accessibility) }
                if Defaults[.hudReplacement] { wanted.insert(.input) }
                if modules.contains(.devices) { wanted.insert(.bluetooth) }
                if modules.contains(.mirror) { wanted.insert(.camera) }
                if modules.contains(.calendar) { wanted.insert(.calendar) }
                if modules.contains(.tasks) { wanted.insert(.reminders) }
                if UserDefaults.standard.bool(forKey:"island.health.reminders") || UserDefaults.standard.bool(forKey:"island.devices.alerts") { wanted.insert(.notifications) }
                if Defaults[.mediaController] == .appleMusic { wanted.insert(.music) }
                if Defaults[.mediaController] == .spotify { wanted.insert(.spotify) }
                if UserDefaults.standard.bool(forKey:"island.schedule.useFocus") { wanted.insert(.focus) }
                if let requested=navigation.requestedPermission { wanted.insert(requested) }
                setup.selected=wanted;setup.hasSuggestedSelection=true
            }
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(1));guard !Task.isCancelled else { return };await setup.refresh() }
        }.onChange(of:navigation.requestedPermission) { if let key=navigation.requestedPermission { setup.selected.insert(key) } }
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
            if state.canSetUp { Button(state == .settings ? "Review…" : "Set up") { Task { await setup.begin([key]) } }.disabled(setup.running || setup.prompting || setup.refreshing) }
            else if state == .allowed { Button("Manage…") { IslandSystemPermissionClient.openSettings(key) }.disabled(setup.running || setup.prompting) }
        }.padding(.vertical,6).accessibilityElement(children:.contain)
    }
}
