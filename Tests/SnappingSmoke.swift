import Foundation
import AppKit
struct SnapFixtureScreen { var frame:CGRect;var visibleFrame:CGRect }
enum SnapFixtureScreens {
    static let screens=[SnapFixtureScreen(frame:CGRect(x:0,y:0,width:1512,height:982),visibleFrame:CGRect(x:0,y:70,width:1512,height:874)),SnapFixtureScreen(frame:CGRect(x:-1920,y:982,width:1920,height:1080),visibleFrame:CGRect(x:-1920,y:1042,width:1920,height:982))]
}
extension Notification.Name { static let accessibilityAuthorizationChanged=Notification.Name("FixtureAuthorization") }
@MainActor final class XPCHelperClient {
    static let shared=XPCHelperClient()
    var captureGate:CheckedContinuation<Void,Never>?
    var readGate:CheckedContinuation<Void,Never>?
    var holdCapture=false,holdRead=false
    var captures=0,reads=0
    var captured:(token:String,pid:Int32,bounds:[Double])?=("fixture",1234,[300,182,800,600])
    var bounds:[Double]?=[0,182,800,600]
    var tiles:[(String,CGRect)]=[]
    var releases:[String]=[]
    func isAccessibilityAuthorized() async -> Bool { false }
    func captureSnapWindow(x:Double,y:Double) async -> (token:String,pid:Int32,bounds:[Double])? {
        captures+=1;let value=captured
        if holdCapture { await withCheckedContinuation { captureGate=$0 } };return value
    }
    func snapWindowBounds(_ token:String) async -> [Double]? {
        reads+=1
        if holdRead { await withCheckedContinuation { readGate=$0 } };return bounds
    }
    func releaseSnapWindow(_ token:String) async { releases.append(token) }
    func tileSnapWindow(_ token:String,x:Double,y:Double,width:Double,height:Double) async -> Bool { tiles.append((token,CGRect(x:x,y:y,width:width,height:height)));return true }
    func reset() { holdCapture=false;holdRead=false;captures=0;reads=0;tiles=[];releases=[];captured=("fixture",1234,[300,182,800,600]);bounds=[0,182,800,600] }
}
@main struct SnappingSmoke {
    @MainActor static func until(_ condition:()->Bool) async {
        for _ in 0..<2000 { if condition() { return };await Task.yield() }
        preconditionFailure("Asynchronous drag did not settle")
    }
    @MainActor static func main() async {
        let client=XPCHelperClient.shared,origin=CGPoint(x:500,y:780)
        let screen=SnapFixtureScreens.screens[0]
        precondition(IslandSnapRules.layout(at:CGPoint(x:756,y:981),in:screen.frame) == .maximize)
        precondition(IslandSnapRules.layout(at:CGPoint(x:756,y:1),in:screen.frame) == .bottom)
        precondition(IslandSnapRules.layout(at:CGPoint(x:1,y:981),in:screen.frame) == .topLeft)
        precondition(IslandSnapRules.cocoaRect([0,0,100,Double.nan],primaryTop:982) == nil)
        precondition(IslandSnapRules.cocoaRect([1,2,3],primaryTop:982) == nil)
        let external=IslandWindowLayout.topLeft.accessibilityRectangle(in:SnapFixtureScreens.screens[1].visibleFrame,primaryTop:982)
        precondition(external == CGRect(x:-1920,y:-1042,width:960,height:491))
        // A quick release while the helper is capturing must be retained.
        let quick=IslandWindowSnapping();client.holdCapture=true
        quick.handle(.leftMouseDown,point:origin);await until { client.captureGate != nil }
        quick.handle(.leftMouseDragged,point:CGPoint(x:1,y:500));quick.handle(.leftMouseUp,point:CGPoint(x:1,y:500))
        client.captureGate?.resume();client.captureGate=nil
        await until { client.tiles.count == 1 && client.releases.count == 1 }
        precondition(client.tiles[0].0 == "fixture" && client.tiles[0].1 == CGRect(x:0,y:38,width:756,height:874))
        // Release during a bounds read uses the final point, not last preview.
        client.reset();client.holdRead=true
        let pending=IslandWindowSnapping();pending.handle(.leftMouseDown,point:origin)
        await until { client.readGate != nil }
        pending.handle(.leftMouseDragged,point:CGPoint(x:1,y:500));pending.handle(.leftMouseUp,point:CGPoint(x:1511,y:500))
        client.readGate?.resume();client.readGate=nil
        await until { client.tiles.count == 1 && client.releases.count == 1 }
        precondition(client.tiles[0].1.minX == 756)
        // Selecting text/dragging a file never moved its containing window.
        client.reset();client.bounds=client.captured!.bounds
        let still=IslandWindowSnapping();still.handle(.leftMouseDown,point:origin);still.handle(.leftMouseDragged,point:CGPoint(x:1,y:500));still.handle(.leftMouseUp,point:CGPoint(x:1,y:500))
        await until { client.releases.count == 1 };precondition(client.tiles.isEmpty)
        // Resizing a window at an edge is not a move gesture.
        client.reset();client.bounds=[0,182,900,600]
        let resized=IslandWindowSnapping();resized.handle(.leftMouseDown,point:origin);resized.handle(.leftMouseUp,point:CGPoint(x:1,y:500))
        await until { client.releases.count == 1 };precondition(client.tiles.isEmpty)
        // Releasing away from an edge must discard a potential target.
        client.reset();let away=IslandWindowSnapping();away.handle(.leftMouseDown,point:origin);away.handle(.leftMouseUp,point:CGPoint(x:700,y:500))
        await until { client.releases.count == 1 };precondition(client.tiles.isEmpty)
        // Local-monitor drags of Island’s own Settings are supported too.
        client.reset();client.captured=("own",ProcessInfo.processInfo.processIdentifier,[300,182,800,600])
        let own=IslandWindowSnapping();own.handle(.leftMouseDown,point:origin);own.handle(.leftMouseUp,point:CGPoint(x:1,y:500))
        await until { client.releases.count == 1 };precondition(client.tiles.count == 1 && client.reads == 1)
        // A second gesture makes a late capture obsolete and releases its token.
        client.reset();client.holdCapture=true
        let stale=IslandWindowSnapping();stale.handle(.leftMouseDown,point:origin);await until { client.captureGate != nil }
        let held=client.captureGate;client.captureGate=nil;client.holdCapture=false;client.captured=nil
        stale.handle(.leftMouseDown,point:origin);await until { client.captures == 2 }
        held?.resume();await until { client.releases.count == 1 };precondition(client.tiles.isEmpty)
        // No reported window yields no resize or guessed app target.
        client.reset();client.captured=nil
        let missing=IslandWindowSnapping();missing.handle(.leftMouseDown,point:origin);missing.handle(.leftMouseUp,point:CGPoint(x:1,y:500))
        await until { client.captures == 1 };for _ in 0..<20 { await Task.yield() };precondition(client.tiles.isEmpty && client.reads == 0)
        print("PASS: 14 production snapping geometry and asynchronous gesture checks; quick release, pending read, exact token, stale capture, resize, text/file drags and missing windows; fake XPC/screens and no desktop interaction")
    }
}
