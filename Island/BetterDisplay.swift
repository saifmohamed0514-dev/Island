import SwiftUI
import AppKit
import CoreGraphics

// Official BetterDisplay request/response protocol. Notifications carry JSON in object,
// so the sandbox stays enabled and no executable, shell or network listener is needed.
struct IslandBetterDisplayRequest:Codable { var uuid:String;var commands:[String];var parameters:[String:String?] }
struct IslandBetterDisplayResponse:Decodable { var uuid:String?;var result:Bool?;var payload:String? }
struct IslandBetterDisplayOSD:Decodable {
    var displayID:Int?;var systemIconID:Int?;var customSymbol:String?;var controlTarget:String?;var value:Double?;var maxValue:Double?;var lock:Bool?
    var fraction:Double? { guard let value,let maxValue,value.isFinite,maxValue.isFinite,maxValue>0 else { return nil };return min(1,max(0,value/maxValue)) }
    var type:String? { if systemIconID==1 || ["brightness","combinedBrightness","hardwareBrightness","softwareBrightness"].contains(controlTarget ?? "") { return "brightness" };if systemIconID==3 || systemIconID==4 || ["volume","mute"].contains(controlTarget ?? "") { return "volume" };return nil }
}
enum IslandBetterDisplayRules {
    static func level(_ payload:String?)->Double? { guard let payload,let value=Double(payload.trimmingCharacters(in:.whitespacesAndNewlines)),value.isFinite,(0...1).contains(value) else { return nil };return value }
    static func parameters(display:UInt32,feature:String,value:Double?)->[String:String?]? {
        guard display>0,["brightness","volume"].contains(feature),value == nil || value!.isFinite && (0...1).contains(value!) else { return nil }
        var p:[String:String?]=["displayID":String(display)];p[feature] = .some(value.map(String.init(describing:)))
        return p
    }
}
@MainActor final class IslandBetterDisplay:NSObject,ObservableObject {
    static let shared=IslandBetterDisplay()
    @Published private(set) var message="Optional. Requires BetterDisplay running with notification integration enabled."
    @Published private(set) var connected=false
    private struct Pending { let continuation:CheckedContinuation<IslandBetterDisplayResponse?,Never>;let timeout:Task<Void,Never> }
    private var pending:[String:Pending]=[:]
    private var observing=false
    private var previousVolume:[UInt32:Double]=[:]
    var enabled:Bool { UserDefaults.standard.bool(forKey:"island.betterDisplay.enabled") }
    var target:CGDirectDisplayID? {
        guard enabled else { return nil }
        let screen=NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let id=(screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,CGDisplayIsBuiltin(id)==0 else { return nil };return id
    }
    func configure() {
        guard enabled else { connected=false;return }
        guard !observing else { return };observing=true
        let center=DistributedNotificationCenter.default()
        center.addObserver(self,selector:#selector(response(_:)),name:.init("pro.betterdisplay.BetterDisplay.response"),object:nil)
        center.addObserver(self,selector:#selector(osd(_:)),name:.init("pro.betterdisplay.BetterDisplay.osd"),object:nil)
    }
    func check() async { configure();guard enabled else { return };let reply=await request(commands:["get"],parameters:["proAvailable":nil]);connected=reply?.result==true;message=connected ? "BetterDisplay responded. Device controls still depend on its hardware and feature support." : "No response. Open BetterDisplay and enable CLI access and notification based integration." }
    func read(display:UInt32,feature:String) async ->Double? {
        guard enabled,let parameters=IslandBetterDisplayRules.parameters(display:display,feature:feature,value:nil) else { return nil }
        let response=await request(commands:["get"],parameters:parameters)
        guard response?.result==true else { message="BetterDisplay couldn’t read that control on this display.";return nil }
        guard let value=IslandBetterDisplayRules.level(response?.payload) else { message="That control didn’t provide a supported level.";return nil };return value
    }
    func toggleMute(display:UInt32) async {
        guard let current=await read(display:display,feature:"volume") else { return }
        if current>0 { previousVolume[display]=current }
        if let actual=await set(display:display,feature:"volume",value:current>0 ? 0 : previousVolume[display] ?? 0.25) { IslandCoordinator.shared.toggleSneakPeek(status:true,type:.volume,value:CGFloat(actual),display:display) }
    }
    func set(display:UInt32,feature:String,value:Double) async ->Double? {
        guard enabled,let parameters=IslandBetterDisplayRules.parameters(display:display,feature:feature,value:value) else { return nil }
        let response=await request(commands:["set"],parameters:parameters)
        guard response?.result==true else { message="BetterDisplay couldn’t change that control. Check the device and its permissions.";return nil }
        // An accepted request is not a physical readback. Refresh instead of inventing success.
        return await read(display:display,feature:feature)
    }
    private func request(commands:[String],parameters:[String:String?]) async ->IslandBetterDisplayResponse? {
        configure();guard enabled,pending.count<8 else { return nil }
        let id=UUID().uuidString
        guard let data=try? JSONEncoder().encode(IslandBetterDisplayRequest(uuid:id,commands:commands,parameters:parameters)),let raw=String(data:data,encoding:.utf8) else { return nil }
        return await withCheckedContinuation { continuation in
            let timeout=Task { @MainActor [weak self] in do { try await Task.sleep(for:.seconds(2)) } catch { return };guard let item=self?.pending.removeValue(forKey:id) else { return };item.continuation.resume(returning:nil) }
            pending[id]=Pending(continuation:continuation,timeout:timeout)
            DistributedNotificationCenter.default().postNotificationName(.init("pro.betterdisplay.BetterDisplay.request"),object:raw,userInfo:nil,deliverImmediately:true)
        }
    }
    @objc private func response(_ notification:Notification) {
        guard let raw=notification.object as? String,raw.utf8.count<16384,let response=try? JSONDecoder().decode(IslandBetterDisplayResponse.self,from:Data(raw.utf8)),let id=response.uuid,let item=pending.removeValue(forKey:id) else { return }
        item.timeout.cancel();item.continuation.resume(returning:response)
    }
    @objc private func osd(_ notification:Notification) {
        guard enabled,let raw=notification.object as? String,raw.utf8.count<16384,let value=try? JSONDecoder().decode(IslandBetterDisplayOSD.self,from:Data(raw.utf8)),let type=value.type,let display=value.displayID,display>0,display<=Int(UInt32.max),let screen=NSScreen.screens.first(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue==display }),let fraction=value.fraction else { return }
        IslandCoordinator.shared.toggleSneakPeek(status:true,type:type=="brightness" ? .brightness : .volume,value:CGFloat(fraction),icon:value.lock==true ? "lock.fill" : value.customSymbol ?? "",display:UInt32(display),locked:value.lock ?? false)
    }
}
struct IslandBetterDisplaySettings:View {
    @ObservedObject private var link=IslandBetterDisplay.shared
    @AppStorage("island.betterDisplay.enabled") private var enabled=false
    @AppStorage("island.betterDisplay.volume") private var volume=false
    var body:some View {
        Section("External displays · BetterDisplay") {
            Toggle("Connect BetterDisplay",isOn:$enabled).onChange(of:enabled) { link.configure();if enabled { Task { await link.check() } } }
            Toggle("Use BetterDisplay for external-display volume keys",isOn:$volume).disabled(!enabled)
            Button("Check Connection") { Task { await link.check() } }.disabled(!enabled)
            Text(link.message).font(.caption).foregroundStyle(.secondary)
            Text("Brightness targets the external display under your pointer. Enable Dispatch OSD notifications in BetterDisplay to show its controls in Island. Choose your overlays there to avoid duplicate feedback. Island keeps its existing preferences intact.").font(.caption).foregroundStyle(.secondary)
            Link("BetterDisplay integration guide",destination:URL(string:"https://betterdisplay.pro/guide/integration/third-party-apps/")!)
        }
    }
}
