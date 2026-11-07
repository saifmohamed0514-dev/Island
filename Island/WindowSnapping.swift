import SwiftUI
import AppKit
import Defaults

enum IslandSnapRules {
    // Detect the physical screen edge. The target rectangle separately uses
    // visibleFrame so a menu bar or Dock never makes an edge unreachable.
    static func layout(at point:CGPoint,in frame:CGRect,margin:CGFloat=20)->IslandWindowLayout? {
        guard point.x.isFinite,point.y.isFinite,frame.width>0,frame.height>0,frame.insetBy(dx:-margin,dy:-margin).contains(point) else { return nil }
        let left=point.x<=frame.minX+margin,right=point.x>=frame.maxX-margin,top=point.y>=frame.maxY-margin,bottom=point.y<=frame.minY+margin
        if left && top { return .topLeft };if right && top { return .topRight };if left && bottom { return .bottomLeft };if right && bottom { return .bottomRight }
        if left { return .left };if right { return .right };if top { return .maximize };if bottom { return .bottom };return nil
    }
    static func cocoaRect(_ values:[Double],primaryTop:CGFloat)->CGRect? {
        guard values.count == 4,values.allSatisfy({ $0.isFinite }),values[2]>0,values[3]>0 else { return nil }
        return CGRect(x:values[0],y:primaryTop-values[1]-values[3],width:values[2],height:values[3])
    }
}
struct IslandSnapDrag {
    let id=UUID()
    let start:CGPoint
    var point:CGPoint
    var released=false
    var token:String?
    var original:CGRect?
    var moved=false
    var resized=false
    mutating func observe(_ frame:CGRect) {
        guard let original else { return }
        if abs(frame.width-original.width)>3 || abs(frame.height-original.height)>3 { resized=true }
        if hypot(frame.minX-original.minX,frame.minY-original.minY)>6 && hypot(point.x-start.x,point.y-start.y)>6 { moved=true }
    }
    func layout(in screen:CGRect)->IslandWindowLayout? { moved && !resized ? IslandSnapRules.layout(at:point,in:screen) : nil }
}
@MainActor final class IslandWindowSnapping:ObservableObject {
    static let shared=IslandWindowSnapping()
    @Published var status="Off"
    private var monitor:Any?
    private var localMonitor:Any?
    private var panel:NSPanel?
    private var generation=UUID()
    private var drag:IslandSnapDrag?
    private var readID:UUID?
    private var lastPoll=Date.distantPast
    private var authorizationObserver:NSObjectProtocol?
    func configure() {
        if authorizationObserver == nil {
            authorizationObserver=NotificationCenter.default.addObserver(forName:.accessibilityAuthorizationChanged,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.configure() } }
        }
        generation=UUID();let configuration=generation
        if let monitor { NSEvent.removeMonitor(monitor);self.monitor=nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor);self.localMonitor=nil };cancel()
        guard UserDefaults.standard.bool(forKey:"island.windows.snap") else { status="Off";return }
        Task { [self] in
            let allowed=await XPCHelperClient.shared.isAccessibilityAuthorized()
            guard generation == configuration else { return }
            guard allowed else { status="Set up Window and system controls in Permissions to enable snapping.";return }
            monitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
                // Capture the event's own location before any asynchronous lookup.
                let top=NSScreen.screens.first?.frame.maxY ?? 0
                let point=event.cgEvent.map { CGPoint(x:$0.location.x,y:top-$0.location.y) } ?? NSEvent.mouseLocation
                let type=event.type
                Task { @MainActor in self?.handle(type,point:point) }
            }
            localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
                let top=NSScreen.screens.first?.frame.maxY ?? 0
                let point=event.cgEvent.map { CGPoint(x:$0.location.x,y:top-$0.location.y) } ?? NSEvent.mouseLocation
                let type=event.type
                Task { @MainActor in self?.handle(type,point:point) }
                return event
            }
            status=monitor == nil ? "macOS didn’t allow the mouse monitor. Try enabling snapping again." : "Ready · drag a window’s title bar to a screen edge"
        }
    }
    private func handle(_ type:NSEvent.EventType,point:CGPoint) {
        switch type {
        case .leftMouseDown:
            cancel();drag=IslandSnapDrag(start:point,point:point)
            let id=drag!.id,configuration=generation,top=NSScreen.screens.first?.frame.maxY ?? 0
            Task {
                let captured=await XPCHelperClient.shared.captureSnapWindow(x:point.x,y:top-point.y)
                guard generation == configuration,drag?.id == id else { if let captured { await XPCHelperClient.shared.releaseSnapWindow(captured.token) };return }
                guard let captured,let rect=IslandSnapRules.cocoaRect(captured.bounds,primaryTop:top) else {
                    if let captured { await XPCHelperClient.shared.releaseSnapWindow(captured.token) };cancel();return
                }
                drag?.token=captured.token;drag?.original=rect
                poll() // Retains drags/releases received while capture was in flight.
            }
        case .leftMouseDragged:
            guard drag != nil else { return };drag?.point=point
            if Date().timeIntervalSince(lastPoll)>0.06 { poll() }
        case .leftMouseUp:
            guard drag != nil else { return };drag?.point=point;drag?.released=true;poll()
        default:break
        }
    }
    private func poll() {
        guard readID == nil,let current=drag,let token=current.token else { return }
        let read=UUID();readID=read;lastPoll=Date()
        Task {
            let values=await XPCHelperClient.shared.snapWindowBounds(token)
            guard readID == read,drag?.id == current.id else { return };readID=nil
            guard let values,let rect=IslandSnapRules.cocoaRect(values,primaryTop:NSScreen.screens.first?.frame.maxY ?? 0) else { cancel();status="This window doesn’t report a movable frame.";return }
            drag?.observe(rect)
            guard let latest=drag else { return }
            let screen=NSScreen.screens.first { $0.frame.contains(latest.point) }
            let layout=screen.flatMap { latest.layout(in:$0.frame) }
            if latest.released {
                // Resolve from the final pointer location, never a stale preview.
                drag=nil;panel?.orderOut(nil)
                if let screen,let layout {
                    let top=NSScreen.screens.first?.frame.maxY ?? 0,target=layout.accessibilityRectangle(in:screen.visibleFrame,primaryTop:top)
                    let success=await XPCHelperClient.shared.tileSnapWindow(token,x:target.minX,y:target.minY,width:target.width,height:target.height)
                    if drag == nil { status=success ? "Applied "+layout.rawValue+" · ready for another window" : "This window couldn’t use that layout. Some apps enforce a minimum size." }
                }
                await XPCHelperClient.shared.releaseSnapWindow(token)
            } else if let screen,let layout { showPreview(layout.rectangle(in:screen.visibleFrame),title:layout.rawValue) }
            else { panel?.orderOut(nil) }
        }
    }
    private func showPreview(_ rect:CGRect,title:String) {
        if panel == nil { let value=NSPanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false);value.isOpaque=false;value.backgroundColor = .clear;value.ignoresMouseEvents=true;value.level = .floating;value.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];value.sharingType=Defaults[.hideFromScreenRecording] ? .none : .readOnly;panel=value }
        panel?.contentView=NSHostingView(rootView:RoundedRectangle(cornerRadius:16).fill(.blue.opacity(0.16)).overlay { RoundedRectangle(cornerRadius:16).stroke(.blue.opacity(0.75),lineWidth:2) }.overlay { Text(title).font(.system(size:18,weight:.semibold)).padding(14).background(.regularMaterial,in:Capsule()) }.padding(4));panel?.setFrame(rect,display:true);panel?.orderFrontRegardless()
    }
    private func cancel() {
        if let token=drag?.token { Task { await XPCHelperClient.shared.releaseSnapWindow(token) } }
        drag=nil;readID=nil;panel?.orderOut(nil)
    }
}
struct IslandWindowSettings:View {
    @AppStorage("island.windows.snap") var snapping=false
    @ObservedObject var monitor=IslandWindowSnapping.shared
    var body:some View {
        Form {
            Section("Snap as you drag") { Toggle("Preview layouts at screen edges",isOn:$snapping);Text("Drag a window’s title bar to the left, right, top or corners, then release. Island checks that the window is moving, so selecting text or dragging a file doesn’t snap it.").foregroundStyle(.secondary);Text(monitor.status).font(.caption).foregroundStyle(.secondary);Button("Manage window access…") { IslandSettingsController.shared.showPermissions(.accessibility) } }
            Section("Manual layouts") { Text("The Window Layouts module also has halves, thirds, corners and Maximize buttons. Some windows enforce minimum sizes, and full-screen windows may not be resizable.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).onChange(of:snapping) { monitor.configure() }
    }
}
