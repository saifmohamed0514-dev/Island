import AppKit

// The notch is a fixed canvas. SwiftUI animates inside it; AppKit must not
// restore, constrain or animate that canvas away from its selected display edge.
class IslandTopEdgePanel:NSPanel {
    private var targetDisplayID:String?
    private var canvasSize=CGSize.zero
    private var repairing=false
    private var repairScheduled=false
    private var edgeObservers:[NSObjectProtocol]=[]
    var displayMetricsProvider:()->[IslandDisplayMetrics] = {
        NSScreen.screens.map { screen in
            IslandDisplayMetrics(id:(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName,
                                 frame:screen.frame,safeTop:screen.safeAreaInsets.top,scale:screen.backingScaleFactor)
        }
    }

    func pin(to screen:NSScreen,canvasSize:CGSize) {
        let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
        pin(displayID:id,canvasSize:canvasSize)
    }
    func pin(displayID:String,canvasSize:CGSize) {
        guard canvasSize.width.isFinite,canvasSize.height.isFinite,canvasSize.width>0,canvasSize.height>0 else { return }
        targetDisplayID=displayID;self.canvasSize=canvasSize
        if edgeObservers.isEmpty {
            for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification,NSWindow.didChangeScreenNotification,NSWindow.didChangeBackingPropertiesNotification] {
                edgeObservers.append(NotificationCenter.default.addObserver(forName:name,object:self,queue:.main) { [weak self] _ in self?.scheduleEdgeRepair() })
            }
            edgeObservers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.scheduleEdgeRepair() })
        }
        repairTopEdge()
    }
    private func pinnedFrame(_ proposed:NSRect)->NSRect {
        guard let id=targetDisplayID,let display=displayMetricsProvider().first(where:{ $0.id==id }),
              !display.frame.isEmpty,[display.frame.minX,display.frame.minY,display.frame.width,display.frame.height].allSatisfy(\.isFinite) else { return proposed }
        return IslandDisplayGeometry.frame(screen:display.frame,size:canvasSize,scale:display.scale)
    }
    override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?)->NSRect { pinnedFrame(frameRect) }
    override func setFrame(_ frameRect:NSRect,display flag:Bool) { super.setFrame(pinnedFrame(frameRect),display:flag) }
    override func setFrame(_ frameRect:NSRect,display flag:Bool,animate:Bool) { super.setFrame(pinnedFrame(frameRect),display:flag,animate:false) }
    override func setFrameOrigin(_ point:NSPoint) {
        let target=pinnedFrame(NSRect(origin:point,size:frame.size))
        super.setFrame(target,display:false)
    }
    override func setFrameTopLeftPoint(_ point:NSPoint) {
        let target=pinnedFrame(NSRect(x:point.x,y:point.y-frame.height,width:frame.width,height:frame.height))
        super.setFrame(target,display:false)
    }
    override func displayIfNeeded() { repairTopEdge();super.displayIfNeeded() }
    func repairTopEdge() {
        guard !repairing else { return }
        let target=pinnedFrame(frame)
        guard target != frame else { return }
        repairing=true;super.setFrame(target,display:false);repairing=false
    }
    private func scheduleEdgeRepair() {
        guard !repairing,!repairScheduled else { return };repairScheduled=true
        DispatchQueue.main.async { [weak self] in self?.repairScheduled=false;self?.repairTopEdge() }
    }
    override func close() { targetDisplayID=nil;super.close() }
    deinit { edgeObservers.forEach { NotificationCenter.default.removeObserver($0) } }
}
