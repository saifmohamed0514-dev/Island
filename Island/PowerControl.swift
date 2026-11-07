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
    init() {
        setupObserver=DistributedNotificationCenter.default().addObserver(forName:Notification.Name("org.islandapp.Island.PowerSetupFinished"),object:nil,queue:.main) { [weak self] note in
            let success=note.object as? String == "ok"
            Task { @MainActor in
                guard let self,self.busy else { return };self.busy=false;self.message=success ? "Setup finished. Checking power controls…" : "Setup wasn’t completed. You can retry or use Battery Settings.";self.connection?.invalidate();self.connection=nil;self.refresh()
            }
        }
        observer=NotificationCenter.default.addObserver(forName:.NSProcessInfoPowerStateDidChange,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() { if !busy { enabled=ProcessInfo.processInfo.isLowPowerModeEnabled };probe() }
    func checkAvailability() async -> Bool {
        await withCheckedContinuation { continuation in
            var finished=false
            @MainActor func finish(_ result:Bool) {
                guard !finished else { return };finished=true;self.available=result
                if !result { self.connection?.invalidate();self.connection=nil }
                continuation.resume(returning:result)
            }
            guard let service=proxy(onError:{ Task { @MainActor in finish(false) } }) else { finish(false);return }
            service.ping { result in Task { @MainActor in finish(result) } }
            Task { try? await Task.sleep(for:.seconds(2));finish(false) }
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
        proxy { [weak self] in self?.available=false;self?.connection?.invalidate();self?.connection=nil }?.ping { [weak self] result in Task { @MainActor in self?.available=result;if result,self?.message.hasPrefix("Setup finished") == true { self?.message="" } } }
    }
    func install() {
        guard !busy else { return };busy=true;message="Approve the one-time macOS setup if prompted."
        let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/IslandPowerSetup.app")
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        NSWorkspace.shared.openApplication(at:helper,configuration:config) { [weak self] _,error in
            Task { @MainActor in if error != nil { self?.busy=false;self?.message="Couldn’t open Island’s setup helper. Reinstall this build or use Battery Settings." } }
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
                    Toggle("Low Power Mode",isOn:Binding(get:{ power.enabled },set:{ power.setEnabled($0) })).labelsHidden().toggleStyle(.switch).tint(.yellow).allowsHitTesting(!power.busy)
                }
            } else { Button(power.busy ? "Setting up…" : "Set up power controls…") { IslandSettingsController.shared.showPermissions(.power) }.disabled(power.busy) }
            if !power.message.isEmpty { Text(power.message).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { power.refresh() }
    }
}
