import AppKit
import SwiftUI
@main struct GuidanceRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let defaults=UserDefaults(suiteName:"IslandGuidanceRender.Fixture")!
        defaults.removePersistentDomain(forName:"IslandGuidanceRender.Fixture")
        defer { defaults.removePersistentDomain(forName:"IslandGuidanceRender.Fixture") }
        let snapshot=IslandDesignerSnapshot(modules:IslandModulePreferences(),canvas:IslandCanvasPreferences(enabled:true,slots:[.home,.shelf,.focus,.notes]))
        let store=IslandSavedLayoutStore.shared
        _=store.save(name:"Work & focus",snapshot:snapshot)
        _=store.save(name:"A quieter evening",snapshot:snapshot)
        for scheme in [ColorScheme.light,.dark] {
            let suffix=scheme == .light ? "light" : "dark"
            try render(IslandGuidanceSettings(),name:"help-"+suffix,width:570,height:650,scheme:scheme,to:folder)
            try render(IslandGuideContent(topic:IslandGuideCatalog.page("System Controls")).padding(20),name:"page-help-"+suffix,width:390,height:510,scheme:scheme,to:folder)
            try render(IslandGuideContent(topic:IslandGuideCatalog.module(.shelf)).padding(20),name:"module-help-"+suffix,width:380,height:320,scheme:scheme,to:folder)
            try render(IslandSavedLayoutsView(snapshot:{ snapshot },apply:{ _ in }),name:"saved-layouts-"+suffix,width:580,height:540,scheme:scheme,to:folder)
        }
    }
    @MainActor static func render<V:View>(_ view:V,name:String,width:CGFloat,height:CGFloat,scheme:ColorScheme,to folder:URL) throws {
        let hosting=NSHostingView(rootView:view.environment(\.colorScheme,scheme).frame(width:width,height:height).background(scheme == .dark ? Color(white:0.12) : Color(white:0.97)))
        hosting.frame=CGRect(x:0,y:0,width:width,height:height);hosting.layoutSubtreeIfNeeded()
        guard let bitmap=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to:folder.appendingPathComponent(name+".png"))
        print("Rendered "+name+" from production views with sample data; no live actions")
    }
}
