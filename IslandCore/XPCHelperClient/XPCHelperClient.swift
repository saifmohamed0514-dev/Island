import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject,IslandMediaKeyListener {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "org.islandapp.Island.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<IslandControlsProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    nonisolated func tileWindow(_ pid: Int32, x: Double, y: Double, width: Double, height: Double) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.tileWindow(pid, x: x, y: y, width: width, height: height) { continuation.resume(returning: $0) }
            }
        } catch { return false }
    }
    nonisolated func windowBounds(_ pid:Int32) async -> [Double]? {
        do { let service=await MainActor.run { ensureRemoteService() };let result:[NSNumber]?=try await service.withContinuation { service,continuation in service.windowBounds(pid) { continuation.resume(returning:$0) } };return result?.map(\.doubleValue) } catch { return nil }
    }
    nonisolated func captureSnapWindow(x:Double,y:Double) async -> (token:String,pid:Int32,bounds:[Double])? {
        do {
            let service=await MainActor.run { ensureRemoteService() }
            let value:(String?,Int32,[NSNumber]?)=try await service.withContinuation { service,continuation in
                service.captureSnapWindow(x,y:y) { token,pid,bounds in continuation.resume(returning:(token,pid,bounds)) }
            }
            guard let token=value.0,let bounds=value.2,bounds.count == 4 else { return nil }
            return (token,value.1,bounds.map(\.doubleValue))
        } catch { return nil }
    }
    nonisolated func snapWindowBounds(_ token:String) async -> [Double]? {
        do { let service=await MainActor.run { ensureRemoteService() };let value:[NSNumber]?=try await service.withContinuation { service,continuation in service.snapWindowBounds(token) { continuation.resume(returning:$0) } };return value?.map(\.doubleValue) } catch { return nil }
    }
    nonisolated func releaseSnapWindow(_ token:String) async {
        let service=await MainActor.run { ensureRemoteService() };try? await service.withService { $0.releaseSnapWindow(token) }
    }
    nonisolated func tileSnapWindow(_ token:String,x:Double,y:Double,width:Double,height:Double) async -> Bool {
        do { let service=await MainActor.run { ensureRemoteService() };return try await service.withContinuation { service,continuation in service.tileSnapWindow(token,x:x,y:y,width:width,height:height) { continuation.resume(returning:$0) } } } catch { return false }
    }
    nonisolated func mediaKey(_ code:Int,modifiers:UInt64,sentAt:Double) {
        Task { @MainActor in MediaKeyInterceptor.shared.receive(code:code,modifiers:modifiers,sentAt:sentAt) }
    }
    @MainActor func startMediaKeys() async -> Bool {
        _ = ensureRemoteService()
        guard let conn=connection else { return false }
        return await withCheckedContinuation { continuation in
            var finished=false
            var timeout:Task<Void,Never>?
            @MainActor func finish(_ value:Bool) {
                guard !finished else { return };finished=true;timeout?.cancel();continuation.resume(returning:value)
            }
            let proxy=conn.remoteObjectProxyWithErrorHandler { _ in Task { @MainActor in finish(false) } } as? IslandControlsProtocol
            guard let proxy else { finish(false);return }
            proxy.startMediaKeys { value in Task { @MainActor in finish(value) } }
            timeout=Task { @MainActor in do { try await Task.sleep(for:.seconds(2)) } catch { return };self.stopMediaKeys();finish(false) }
        }
    }
    @MainActor func stopMediaKeys() {
        guard let connection else { return }
        (connection.remoteObjectProxyWithErrorHandler { _ in } as? IslandControlsProtocol)?.stopMediaKeys()
    }
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<IslandControlsProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self,weak conn] in
            Task { @MainActor in
                guard self?.connection === conn else { return }
                self?.connection = nil
                self?.remoteService = nil
                MediaKeyInterceptor.shared.connectionLost()
            }
        }
        
        conn.invalidationHandler = { [weak self,weak conn] in
            Task { @MainActor in
                guard self?.connection === conn else { return }
                self?.connection = nil
                self?.remoteService = nil
                MediaKeyInterceptor.shared.connectionLost()
            }
        }
        
        conn.exportedInterface=NSXPCInterface(with:IslandMediaKeyListener.self)
        conn.exportedObject=self
        conn.resume()
        
        let service = RemoteXPCService<IslandControlsProtocol>(
            connection: conn,
            remoteInterface: IslandControlsProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<IslandControlsProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        await accessibilityAuthorizationStatus() ?? false
    }

    // nil is a service problem, not a denial. A dead helper must not leave the
    // entire Permissions page spinning or erase a grant with a stale reply.
    @MainActor func accessibilityAuthorizationStatus() async -> Bool? {
        _ = ensureRemoteService()
        guard let conn=connection else { return nil }
        return await withCheckedContinuation { continuation in
            var finished=false
            var timeout:Task<Void,Never>?
            @MainActor func finish(_ value:Bool?) {
                guard !finished else { return };finished=true;timeout?.cancel()
                if let value { self.notifyAuthorizationChange(value) }
                else if self.connection === conn { self.connection=nil;self.remoteService=nil;conn.invalidate() }
                continuation.resume(returning:value)
            }
            let proxy=conn.remoteObjectProxyWithErrorHandler { _ in Task { @MainActor in finish(nil) } } as? IslandControlsProtocol
            guard let proxy else { finish(nil);return }
            proxy.isAccessibilityAuthorized { value in Task { @MainActor in finish(value) } }
            timeout=Task { @MainActor in
                do { try await Task.sleep(for:.seconds(2)) } catch { return }
                finish(nil)
            }
        }
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


