import SwiftUI
import Combine
import AppKit
import IOKit
import IOBluetooth

@MainActor final class IslandDevices: ObservableObject {
    struct Device: Identifiable { var id:String; var name:String; var battery:Int?; var connected:Bool }
    @Published var devices:[Device] = []
    @Published var status = "Refresh to read paired devices and available battery levels."
    func refresh() {
        var result:[String:Device] = [:]
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired where device.isConnected() {
            let name = device.name ?? "Bluetooth Device"
            result[name] = Device(id:name,name:name,battery:nil,connected:true)
        }
        var iterator:io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleDeviceManagementHIDEventService"),&iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                let name = IORegistryEntryCreateCFProperty(service,"Product" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String ?? "Input Device"
                let battery = (IORegistryEntryCreateCFProperty(service,"BatteryPercent" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber)?.intValue
                if let battery, (0...100).contains(battery) { result[name] = Device(id:name,name:name,battery:battery,connected:true) }
                IOObjectRelease(service); service = IOIteratorNext(iterator)
            }
        }
        devices = result.values.sorted { $0.name < $1.name }
        status = devices.isEmpty ? "No connected devices reported. Review Bluetooth permission if needed." : "Battery levels are shown only when macOS reports them."
    }
}
struct IslandDevicesView: View {
    @StateObject var model = IslandDevices()
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Bluetooth & Devices").font(.headline); Spacer(); Button("Refresh") { model.refresh() } }
            ForEach(model.devices) { device in
                HStack { Image(systemName:"antenna.radiowaves.left.and.right"); Text(device.name); Spacer(); if let battery = device.battery { Text("\(battery)%").foregroundStyle(battery <= 20 ? .orange : .secondary) } else { Text("Connected").foregroundStyle(.secondary) } }
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
