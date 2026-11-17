import AppKit
import SwiftUI

@main struct TopEdgePanelSmoke {
    @MainActor static func main() async {
        _=NSApplication.shared
        var count=0
        func check(_ value:Bool) { precondition(value,"Pinned panel check \(count+1)");count+=1 }
        let canvas=CGSize(width:680,height:236)
        var displays=[IslandDisplayMetrics(id:"main",frame:CGRect(x:0,y:0,width:1710,height:1107),safeTop:33.5,scale:2)]
        let panel=IslandTopEdgePanel(contentRect:CGRect(origin:.zero,size:canvas),styleMask:[.borderless,.nonactivatingPanel,.utilityWindow,.hudWindow],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false
        panel.displayMetricsProvider={ displays }
        let hosting=NSHostingView(rootView:Color.black.frame(width:canvas.width,height:canvas.height,alignment:.top))
        hosting.safeAreaRegions=[];panel.contentView=hosting
        panel.pin(displayID:"main",canvasSize:canvas)
        func flush() { if panel.frame.maxY != displays[0].frame.maxY || panel.frame.size != canvas { print("Actual",panel.frame,"expected",displays[0].frame,"scale",displays[0].scale);fflush(stdout) };check(panel.frame.maxY==displays[0].frame.maxY && panel.frame.size==canvas) }
        flush();check(panel.frame.midX==displays[0].frame.midX)
        // The screenshot's four-pixel gap is a two-point shifted proposal at 2x.
        let shifted=panel.frame.offsetBy(dx:0,dy:-2)
        check(panel.constrainFrameRect(shifted,to:nil).maxY==displays[0].frame.maxY)
        panel.setFrame(shifted,display:false);flush()
        panel.setFrameOrigin(CGPoint(x:30,y:30));flush()
        panel.setFrameTopLeftPoint(CGPoint(x:50,y:1105));flush()
        panel.setFrame(CGRect(x:30,y:30,width:320,height:80),display:false,animate:true);flush()
        hosting.layoutSubtreeIfNeeded();check(hosting.frame.size==canvas && hosting.frame.maxY==canvas.height)
        check(!panel.isVisible) // All tests remain offscreen; no desktop input.
        displays=[.init(id:"main",frame:CGRect(x:-1920,y:1080,width:1920,height:1080),safeTop:0,scale:1)]
        NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil)
        try? await Task.sleep(for:.milliseconds(30));flush()
        check(panel.frame.midX==displays[0].frame.midX)
        // AppKit quantizes offscreen fixture windows against the actual Mac,
        // so keep the simulated top edge on a representable point boundary.
        displays=[.init(id:"main",frame:CGRect(x:0.25,y:-900,width:1536,height:900),safeTop:0,scale:1.5)]
        panel.repairTopEdge();flush()
        check(abs(panel.frame.midX-displays[0].frame.midX)<=0.5/1.5)
        displays=[.init(id:"other",frame:CGRect(x:100,y:0,width:1920,height:1080),safeTop:0,scale:2)]
        panel.pin(displayID:"other",canvasSize:canvas);flush()
        let before=panel.frame;panel.pin(displayID:"other",canvasSize:CGSize(width:CGFloat.nan,height:236));check(panel.frame==before)
        displays=[]
        let ordinary=CGRect(x:40,y:60,width:400,height:200)
        panel.setFrame(ordinary,display:false);check(panel.frame==ordinary)
        displays=[.init(id:"other",frame:CGRect(x:100,y:0,width:1920,height:1080),safeTop:0,scale:2)]
        NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil)
        try? await Task.sleep(for:.milliseconds(30));flush()
        panel.close()
        panel.setFrame(ordinary,display:false);check(panel.frame==ordinary)
        print("PASS: \(count) production native-panel checks; shifted constraints, frame/origin/top-left setters, animation suppression, fixed canvas, zero content inset, screen/scale changes, display removal/reconnect and close; no window shown or input posted")
    }
}
