import SwiftUI
import AppKit
import Defaults

enum IslandSnapRules {
    static func layout(at point:CGPoint,in frame:CGRect,margin:CGFloat=20)->IslandWindowLayout? {
        guard frame.insetBy(dx:-margin,dy:-margin).contains(point) else { return nil }
        let left=point.x<=frame.minX+margin,right=point.x>=frame.maxX-margin,top=point.y>=frame.maxY-margin,bottom=point.y<=frame.minY+margin
        if left && top { return .topLeft };if right && top { return .topRight };if left && bottom { return .bottomLeft };if right && bottom { return .bottomRight }
        if left { return .left };if right { return .right };if top { return .maximize };if bottom { return .bottom };return nil
    }
}
@MainActor final class IslandWindowSnapping:ObservableObject {
    static let shared=IslandWindowSnapping()
    @Published var status="Off"
    private var monitor:Any?
    private var panel:NSPanel?
    private var generation=UUID()
    private var gesture=UUID()
    private var drag:(id:UUID,pid:Int32,original:CGRect)?
    private var target:(layout:IslandWindowLayout,frame:CGRect,screenFrame:CGRect)?
    private var lastPoll=Date.distantPast
    private var reading=false
    func configure() {
        generation=UUID();let token=generation
        if let monitor { NSEvent.removeMonitor(monitor);self.monitor=nil };cancel()
        guard UserDefaults.standard.bool(forKey:"island.windows.snap") else { status="Off";return }
        Task {
            guard await XPCHelperClient.shared.isAccessibilityAuthorized(),generation == token else { status="Allow Accessibility in System Controls, then try again.";return }
            monitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in Task { @MainActor in self?.handle(event.type) } }
            status=monitor == nil ? "macOS didn’t allow the mouse monitor." : "Ready · drag a window’s title bar to a screen edge"
        }
    }
    private func handle(_ type:NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            cancel();guard let app=NSWorkspace.shared.frontmostApplication,app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            let token=generation,gesture=self.gesture,pid=app.processIdentifier,point=NSEvent.mouseLocation
            Task {
                guard let rect=await bounds(pid),generation == token,self.gesture == gesture else { return }
                if point.x >= rect.minX && point.x<=rect.maxX && point.y>=rect.maxY-38 && point.y<=rect.maxY { drag=(UUID(),pid,rect) }
            }
        case .leftMouseDragged:
            guard let drag,!reading,Date().timeIntervalSince(lastPoll)>0.1 else { return };reading=true;lastPoll=Date()
            Task {
                defer { reading=false }
                guard let current=await bounds(drag.pid),self.drag?.id == drag.id,NSWorkspace.shared.frontmostApplication?.processIdentifier == drag.pid else { return }
                guard abs(current.width-drag.original.width)<3,abs(current.height-drag.original.height)<3,hypot(current.minX-drag.original.minX,current.minY-drag.original.minY)>6 else { target=nil;panel?.orderOut(nil);return }
                let point=NSEvent.mouseLocation
                guard let screen=NSScreen.screens.first(where:{ $0.frame.contains(point) }),let layout=IslandSnapRules.layout(at:point,in:screen.visibleFrame) else { target=nil;panel?.orderOut(nil);return }
                let rect=layout.rectangle(in:screen.visibleFrame);target=(layout,rect,screen.visibleFrame);showPreview(rect,title:layout.rawValue)
            }
        case .leftMouseUp:
            let drag=self.drag,target=self.target;cancel()
            guard let drag,let target,NSWorkspace.shared.frontmostApplication?.processIdentifier == drag.pid,IslandSnapRules.layout(at:NSEvent.mouseLocation,in:target.screenFrame) == target.layout else { return }
            let top=NSScreen.screens.first?.frame.maxY ?? 0,rect=target.frame
            Task { let success=await XPCHelperClient.shared.tileWindow(drag.pid,x:rect.minX,y:top-rect.maxY,width:rect.width,height:rect.height);if !success { status="This window couldn’t use that layout. Some apps enforce a minimum size." } }
        default:break
        }
    }
    private func bounds(_ pid:Int32) async -> CGRect? {
        guard let values=await XPCHelperClient.shared.windowBounds(pid),values.count == 4 else { return nil }
        let top=NSScreen.screens.first?.frame.maxY ?? 0;return CGRect(x:values[0],y:top-values[1]-values[3],width:values[2],height:values[3])
    }
    private func showPreview(_ rect:CGRect,title:String) {
        if panel == nil { let value=NSPanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false);value.isOpaque=false;value.backgroundColor = .clear;value.ignoresMouseEvents=true;value.level = .floating;value.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];value.sharingType=Defaults[.hideFromScreenRecording] ? .none : .readOnly;panel=value }
        panel?.contentView=NSHostingView(rootView:RoundedRectangle(cornerRadius:16).fill(.blue.opacity(0.16)).overlay { RoundedRectangle(cornerRadius:16).stroke(.blue.opacity(0.75),lineWidth:2) }.overlay { Text(title).font(.system(size:18,weight:.semibold)).padding(14).background(.regularMaterial,in:Capsule()) }.padding(4));panel?.setFrame(rect,display:true);panel?.orderFrontRegardless()
    }
    private func cancel() { gesture=UUID();drag=nil;target=nil;panel?.orderOut(nil) }
}
struct IslandWindowSettings:View {
    @AppStorage("island.windows.snap") var snapping=false
    @ObservedObject var monitor=IslandWindowSnapping.shared
    var body:some View {
        Form {
            Section("Snap as you drag") { Toggle("Preview layouts at screen edges",isOn:$snapping);Text("Drag a window’s title bar to the left, right, top or corners, then release. Island checks that the window is moving, so selecting text or dragging a file doesn’t snap it.").foregroundStyle(.secondary);Text(monitor.status).font(.caption).foregroundStyle(.secondary);Button("Check Accessibility and try again") { Task { _=await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded:true);monitor.configure() } } }
            Section("Manual layouts") { Text("The Window Layouts module also has halves, thirds, corners and Maximize buttons. Some windows enforce minimum sizes, and full-screen windows may not be resizable.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).onChange(of:snapping) { monitor.configure() }
    }
}
