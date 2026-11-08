import SwiftUI
import Combine
import Security

@objc(IslandPowerControl) protocol IslandPowerControl {
    func ping(with reply:@escaping(Bool)->Void)
    func setLowPowerMode(_ enabled:Bool,onACPower:Bool,with reply:@escaping(Bool)->Void)
}
@MainActor final class IslandPowerController:ObservableObject {
    static let shared=IslandPowerController()
    @Published var enabled=ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var available=false
    @Published var busy=false
    @Published var message=""
    private var connection:NSXPCConnection?
    private var operation:UUID?
    private var observer:NSObjectProtocol?
    private var setupObserver:NSObjectProtocol?
    private var setupApplication:NSRunningApplication?
    private var setupWatch:Task<Void,Never>?
    private var installation:UUID?
    private var installationFinishing=false
    private var availabilityTask:Task<Bool,Never>?
    private var availabilityID=UUID()
    init() {
        setupObserver=DistributedNotificationCenter.default().addObserver(forName:Notification.Name("org.islandapp.Island.PowerSetupFinished"),object:nil,queue:.main) { [weak self] note in
            // This notification is only a hint. Trust the authenticated service
            // probe, never a success string broadcast by another process.
            Task { @MainActor in
                guard let self,self.setupApplication?.isTerminated == true else { return }
                self.finishInstallation()
            }
        }
        observer=NotificationCenter.default.addObserver(forName:.NSProcessInfoPowerStateDidChange,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() { if !busy { enabled=ProcessInfo.processInfo.isLowPowerModeEnabled };probe() }
    func checkAvailability() async -> Bool {
        if let availabilityTask { return await availabilityTask.value }
        let id=UUID();availabilityID=id
        let task=Task { @MainActor in await self.probeAvailability() }
        availabilityTask=task
        let result=await task.value
        if availabilityID == id { availabilityTask=nil }
        return result
    }
    private func probeAvailability() async -> Bool {
        await withCheckedContinuation { continuation in
            var finished=false
            var checkedConnection:NSXPCConnection?
            var timeout:Task<Void,Never>?
            @MainActor func finish(_ result:Bool) {
                guard !finished else { return };finished=true;timeout?.cancel()
                if checkedConnection === self.connection {
                    self.available=result
                    if !result { self.connection?.invalidate();self.connection=nil }
                }
                continuation.resume(returning:result)
            }
            guard let service=proxy(onError:{ Task { @MainActor in finish(false) } }) else { finish(false);return }
            checkedConnection=connection
            service.ping { result in Task { @MainActor in finish(result) } }
            timeout=Task { @MainActor in do { try await Task.sleep(for:.seconds(2)) } catch { return };finish(false) }
        }
    }
    private func proxy(onError:@escaping()->Void)->IslandPowerControl? {
        if connection == nil {
            let connection=NSXPCConnection(machServiceName:"org.islandapp.Island.Power",options:.privileged)
            connection.remoteObjectInterface=NSXPCInterface(with:IslandPowerControl.self);connection.resume();self.connection=connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in Task { @MainActor in onError() } } as? IslandPowerControl
    }
    private func probe() {
        guard !busy else { return }
        Task { @MainActor in _ = await checkAvailability() }
    }
    func install() {
        guard !busy else { return };busy=true;message="Approve the one-time macOS setup if prompted."
        installation=UUID();installationFinishing=false
        let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/IslandPowerSetup.app")
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        NSWorkspace.shared.openApplication(at:helper,configuration:config) { [weak self] application,error in
            Task { @MainActor in
                guard let self,self.installation != nil else { return }
                guard error == nil,let application else { self.installation=nil;self.busy=false;self.message="Couldn’t open Island’s setup helper. Reinstall this build or use Battery Settings.";return }
                self.setupApplication=application
                self.setupWatch=Task { @MainActor [weak self,weak application] in
                    // Distributed notifications can be dropped. Watch only our
                    // own setup process so completion/cancel always clears busy.
                    while let application,!application.isTerminated {
                        do { try await Task.sleep(for:.seconds(1)) } catch { return }
                    }
                    self?.finishInstallation()
                }
            }
        }
    }
    private func finishInstallation() {
        guard let id=installation,operation == nil,!installationFinishing else { return }
        installationFinishing=true
        setupWatch?.cancel();setupWatch=nil;setupApplication=nil
        Task { @MainActor in
            // Finish any older read before reconnecting to the newly installed service.
            if let availabilityTask { _ = await availabilityTask.value }
            availabilityTask=nil;availabilityID=UUID()
            connection?.invalidate();connection=nil
            let ready=await checkAvailability()
            guard installation == id else { return }
            installation=nil;busy=false;enabled=ProcessInfo.processInfo.isLowPowerModeEnabled
            message=ready ? "Power controls are ready." : "Setup wasn’t completed. Choose Set up to try again, or use Battery Settings."
        }
    }
    func setEnabled(_ desired:Bool) {
        guard available,!busy,desired != enabled else { return }
        let id=UUID();operation=id;busy=true;enabled=desired;message=""
        func finish(_ success:Bool) {
            guard self.operation == id else { return };self.operation=nil;self.busy=false
            self.enabled=ProcessInfo.processInfo.isLowPowerModeEnabled
            if !success || self.enabled != desired { self.message="macOS didn’t confirm the change. Check Battery Settings or enable power controls again after an app update." }
        }
        let ac=BatteryStatusViewModel.shared.isPluggedIn
        proxy { finish(false) }?.setLowPowerMode(desired,onACPower:ac) { result in
            Task { @MainActor in
                // Reconcile the operating-system state after its notification settles; do not animate a second toggle.
                if result { for _ in 0..<20 { if ProcessInfo.processInfo.isLowPowerModeEnabled == desired { break };try? await Task.sleep(for:.milliseconds(100)) } }
                finish(result)
            }
        }
        Task { try? await Task.sleep(for:.seconds(5));finish(false) }
    }
}
struct IslandPowerSwitch:View {
    @ObservedObject var power=IslandPowerController.shared
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if power.available {
                HStack {
                    Text("Low Power Mode").accessibilityHidden(true);Spacer()
                    if power.busy { ProgressView().controlSize(.mini).accessibilityLabel("Updating power mode") }
                    Toggle("Low Power Mode",isOn:Binding(get:{ power.enabled },set:{ IslandHaptics.play(.selection);power.setEnabled($0) })).labelsHidden().toggleStyle(.switch).tint(.yellow).allowsHitTesting(!power.busy)
                }
            } else { Button(power.busy ? "Setting up…" : "Set up power controls…") { IslandSettingsController.shared.showPermissions(.power) }.disabled(power.busy) }
            if !power.message.isEmpty { Text(power.message).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { power.refresh() }
    }
}
