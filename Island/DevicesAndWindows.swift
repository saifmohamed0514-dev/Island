import SwiftUI
import Combine
import AppKit
import IOKit
import IOBluetooth

@MainActor final class IslandDevices:ObservableObject {
    static let shared=IslandDevices()
    struct Device:Identifiable { var id:String;var name:String;var battery:Int?;var parts:[String:Int]=[:];var connected:Bool }
    @Published var devices:[Device]=[]
    @Published var status="Refresh to read connected devices and available battery levels."
    private var clock:Task<Void,Never>?
    private var previous:[String:Int]=[:]
    func configure(_ enabled:Bool) {
        clock?.cancel();clock=nil
        guard enabled,UserDefaults.standard.bool(forKey:"island.devices.alerts") else { return }
        clock=Task { [weak self] in while !Task.isCancelled { self?.refresh();try? await Task.sleep(for:.seconds(60)) } }
    }
    func refresh() {
        var result:[String:Device]=[:]
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            let name=device.name ?? "Bluetooth Device",id=device.addressString ?? name
            result[id]=Device(id:id,name:name,battery:nil,connected:true)
        }
        for className in ["AppleDeviceManagementHIDEventService","IOBluetoothDevice"] {
            var iterator:io_iterator_t=0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching(className),&iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) };var service=IOIteratorNext(iterator)
            while service != 0 {
                func property(_ key:String)->Any? { IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
                let name=property("Product") as? String ?? property("Name") as? String ?? "Input Device"
                let address=property("DeviceAddress") as? String
                let known=result.values.first { $0.name == name || (address != nil && $0.id == address) }
                if className != "IOBluetoothDevice" || known != nil || (property("Connected") as? Bool == true) {
                    var parts:[String:Int]=[:]
                    for (label,key) in [("Battery","BatteryPercent"),("Left","BatteryPercentLeft"),("Right","BatteryPercentRight"),("Case","BatteryPercentCase")] {
                        if let level=(property(key) as? NSNumber)?.intValue,(0...100).contains(level) { parts[label]=level }
                    }
                    if !parts.isEmpty {
                        let id=known?.id ?? address ?? name
                        result[id]=Device(id:id,name:known?.name ?? name,battery:parts["Battery"] ?? parts.values.min(),parts:parts,connected:true)
                    }
                }
                IOObjectRelease(service);service=IOIteratorNext(iterator)
            }
        }
        devices=result.values.sorted { $0.name < $1.name }
        if UserDefaults.standard.bool(forKey:"island.devices.alerts") {
            let threshold=UserDefaults.standard.object(forKey:"island.devices.threshold") as? Int ?? 20
            for device in devices {
                guard let level=device.battery else { continue }
                if IslandDeviceAlertRules.shouldWarn(level:level,threshold:threshold,previous:previous[device.id]) {
                    let key="island.device.warned."+Data(device.id.utf8).base64EncodedString()
                    let last=UserDefaults.standard.double(forKey:key)
                    if Date().timeIntervalSince1970-last > 6*3600 { IslandNotices.shared.post(title:"\(device.name) battery is low",body:"\(level)% remaining. Connect it to power when convenient.",source:"Devices");UserDefaults.standard.set(Date().timeIntervalSince1970,forKey:key) }
                }
                previous[device.id]=level
            }
        }
        status=devices.isEmpty ? "No connected devices reported. Review Bluetooth access if needed." : "Levels and separate earbuds/case appear only when macOS reports them."
    }
}
struct IslandDevicesView:View {
    @ObservedObject var model=IslandDevices.shared
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Bluetooth & Devices").font(.headline);Spacer();Button("Refresh") { model.refresh() } }
            ForEach(model.devices) { device in
                HStack { Image(systemName:"antenna.radiowaves.left.and.right");Text(device.name);Spacer();if !device.parts.isEmpty { Text(device.parts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)%" }.joined(separator:" · ")).font(.caption).foregroundStyle((device.battery ?? 100) <= 20 ? .orange : .secondary) } else { Text("Connected").foregroundStyle(.secondary) } }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
enum IslandWindowLayout:String,CaseIterable,Identifiable {
    var id:String { rawValue }
    case left = "Left Half", right = "Right Half", top = "Top Half", bottom = "Bottom Half", firstThird = "Left Third", middleThird = "Middle Third", lastThird = "Right Third", topLeft = "Top Left", topRight = "Top Right", bottomLeft = "Bottom Left", bottomRight = "Bottom Right", maximize = "Maximize"
    var fraction:CGRect {
        switch self {
        case .left:return CGRect(x:0,y:0,width:0.5,height:1)
        case .right:return CGRect(x:0.5,y:0,width:0.5,height:1)
        case .top:return CGRect(x:0,y:0.5,width:1,height:0.5)
        case .bottom:return CGRect(x:0,y:0,width:1,height:0.5)
        case .firstThird:return CGRect(x:0,y:0,width:1.0/3,height:1)
        case .middleThird:return CGRect(x:1.0/3,y:0,width:1.0/3,height:1)
        case .lastThird:return CGRect(x:2.0/3,y:0,width:1.0/3,height:1)
        case .topLeft:return CGRect(x:0,y:0.5,width:0.5,height:0.5)
        case .topRight:return CGRect(x:0.5,y:0.5,width:0.5,height:0.5)
        case .bottomLeft:return CGRect(x:0,y:0,width:0.5,height:0.5)
        case .bottomRight:return CGRect(x:0.5,y:0,width:0.5,height:0.5)
        case .maximize:return CGRect(x:0,y:0,width:1,height:1)
        }
    }
    func accessibilityRectangle(in frame:CGRect, primaryTop:CGFloat) -> CGRect { let cocoa = rectangle(in:frame); return CGRect(x:cocoa.minX,y:primaryTop-cocoa.maxY,width:cocoa.width,height:cocoa.height) }
    func rectangle(in frame:CGRect) -> CGRect { let r = fraction; return CGRect(x:frame.minX+r.minX*frame.width,y:frame.minY+r.minY*frame.height,width:r.width*frame.width,height:r.height*frame.height) }
}
struct IslandWindowSnapView: View {
    @EnvironmentObject var vm:IslandViewModel
    @State var target:Int32 = 0
    @State var apps:[NSRunningApplication] = []
    @State var status = "Choose an app, then a layout."
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Picker("App",selection:$target) { ForEach(apps,id:\.processIdentifier) { app in Text(app.localizedName ?? "App").tag(app.processIdentifier) } }
                Button("Allow Accessibility…") { Task { await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true) } }
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:6) {
                ForEach(IslandWindowLayout.allCases) { layout in Button(layout.rawValue) { snap(layout) }.buttonStyle(.bordered).disabled(target == 0) }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }.onAppear {
            apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            target = apps.first(where: { $0.isActive })?.processIdentifier ?? apps.first?.processIdentifier ?? 0
        }
    }
    func snap(_ layout:IslandWindowLayout) {
        guard let screen = vm.screenUUID.flatMap({ NSScreen.screen(withUUID:$0) }) ?? NSScreen.main else { return }
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let rect = layout.accessibilityRectangle(in:screen.visibleFrame,primaryTop:mainTop)
        Task {
            let success = await XPCHelperClient.shared.tileWindow(target,x:rect.minX,y:rect.minY,width:rect.width,height:rect.height)
            status = success ? "Applied \(layout.rawValue)." : "Couldn’t resize this window. Check Accessibility access; some apps enforce a minimum size."
        }
    }
}
