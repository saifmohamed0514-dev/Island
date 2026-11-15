import SwiftUI
import AppKit

struct IslandSwipeAccumulator {
    private var accumulated=0.0
    private var consumed=false
    private var lastTime=0.0
    mutating func consume(x:Double,y:Double,began:Bool,momentum:Bool,time:Double,natural:Bool)->Bool? {
        guard x.isFinite,y.isFinite,time.isFinite else { self=Self();return nil }
        guard !momentum else { return nil }
        if began || time<lastTime || time-lastTime>0.3 { accumulated=0;consumed=false }
        lastTime=time
        guard abs(x)>abs(y) else { return nil }
        accumulated=min(10000,max(-10000,accumulated+x))
        guard abs(accumulated)>40,!consumed else { return nil }
        consumed=true;return (accumulated<0) != (!natural)
    }
}
// Monitors only this view's own window and bounds. No global input or permission.
struct IslandActivityInput:NSViewRepresentable {
    var middleClick:Bool
    var horizontal:Bool
    var onCycle:()->Void
    var onSkip:(Bool)->Void
    func makeCoordinator()->Coordinator { Coordinator(configuration:self) }
    func makeNSView(context:Context)->NSView {
        let view=NSView();context.coordinator.install(view);return view
    }
    func updateNSView(_ view:NSView,context:Context) { context.coordinator.configuration=self }
    static func dismantleNSView(_ view:NSView,coordinator:Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        var configuration:IslandActivityInput
        private var monitor:Any?
        private var swipe=IslandSwipeAccumulator()
        init(configuration:IslandActivityInput) { self.configuration=configuration }
        func install(_ view:NSView) {
            stop()
            monitor=NSEvent.addLocalMonitorForEvents(matching:[.otherMouseUp,.scrollWheel]) { [weak self,weak view] event in
                guard let self,let view,let window=view.window,event.window === window,view.bounds.contains(view.convert(event.locationInWindow,from:nil)) else { return event }
                if event.type == .otherMouseUp,event.buttonNumber==2,self.configuration.middleClick { self.configuration.onCycle();return nil }
                guard event.type == .scrollWheel,self.configuration.horizontal,event.momentumPhase.isEmpty else { return event }
                let natural=UserDefaults.standard.object(forKey:"island.gesture.natural") as? Bool ?? true
                let forward=self.swipe.consume(x:event.scrollingDeltaX,y:event.scrollingDeltaY,began:event.phase.contains(.began),momentum:!event.momentumPhase.isEmpty,time:ProcessInfo.processInfo.systemUptime,natural:natural)
                guard abs(event.scrollingDeltaX)>abs(event.scrollingDeltaY) else { return event }
                if let forward { self.configuration.onSkip(forward) }
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) };monitor=nil;swipe=IslandSwipeAccumulator() }
    }
}
