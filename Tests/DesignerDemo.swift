import AppKit
import SwiftUI
@MainActor final class DesignerDemoDelegate:NSObject,NSApplicationDelegate {
    private var window:NSWindow?
    private let domain="org.islandapp.CanvasCheck.Fixture"
    func applicationDidFinishLaunching(_ notification:Notification) {
        let defaults=UserDefaults(suiteName:domain)!
        defaults.removePersistentDomain(forName:domain)
        defaults.set(false,forKey:"island.designer.inspector")
        defaults.set("focus",forKey:"island.designer.selected")
        defaults.set("Sample City",forKey:"island.weather.city")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:610),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Island layout check · Sample data"
        window.contentView=NSHostingView(rootView:IslandModuleDesigner().defaultAppStorage(defaults).frame(width:560,height:610))
        window.center();window.makeKeyAndOrderFront(nil);self.window=window
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationWillTerminate(_ notification:Notification) { UserDefaults(suiteName:domain)?.removePersistentDomain(forName:domain) }
}
@main struct DesignerDemo {
    @MainActor static func main() {
        let app=NSApplication.shared,delegate=DesignerDemoDelegate()
        app.setActivationPolicy(.regular);app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
