import AppKit
import SwiftUI
@main struct DesignerRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        for (name,selected,scheme) in [("designer-light",NotchViews.focus,ColorScheme.light),("designer-dark",.weather,.dark)] {
            let domain="IslandDesignerRender-"+UUID().uuidString
            let defaults=UserDefaults(suiteName:domain)!
            defer { defaults.removePersistentDomain(forName:domain) }
            defaults.set(selected.rawValue,forKey:"island.designer.selected")
            defaults.set(false,forKey:"island.designer.inspector")
            defaults.set("Sample City",forKey:"island.weather.city")
            let content=IslandModuleDesigner().defaultAppStorage(defaults).environment(\.colorScheme,scheme)
                .frame(width:560,height:610).background(scheme == .dark ? Color(white:0.12) : Color(white:0.97))
            let hosting=NSHostingView(rootView:content)
            hosting.frame=CGRect(x:0,y:0,width:560,height:610)
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
            hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to:folder.appendingPathComponent(name+".png"))
            print("Rendered \(name).png from production views with sample data; no live module actions executed")
        }
    }
}
