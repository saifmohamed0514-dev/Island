import AppKit
import SwiftUI
@main struct PluginTraysRender {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),suite="IslandPluginRender.Fixture",defaults=UserDefaults(suiteName:suite)!
  defaults.removePersistentDomain(forName:suite);defer { defaults.removePersistentDomain(forName:suite) }
  let bridge=IslandAgentBridge()
  func event(question:Bool)->IslandAgentBridge.Event {
   let json:[String:Any]=["id":UUID().uuidString,"nonce":UUID().uuidString,"provider":"chatgpt-plugin","event":question ? "Question" : "Progress","session":"sample","time":Date().timeIntervalSince1970,"expires":Date().timeIntervalSince1970+300,"approval":false,"title":question ? "Which layout would you prefer?" : "Refining your Island","message":"The new tray controls are built. Checking their layout and keyboard behavior.","request":"","kind":question ? "question" : "progress","options":["Music and focus","A quieter layout"],"state":question ? "waiting" : "working","percent":65]
   return try! JSONDecoder().decode(IslandAgentBridge.Event.self,from:JSONSerialization.data(withJSONObject:json))
  }
  for scheme in [ColorScheme.light,.dark] {
   let suffix=scheme == .light ? "light" : "dark"
   try render(IslandTraysSettings(),name:"trays-open-"+suffix,width:570,height:650,scheme:scheme,to:folder,defaults:defaults)
   try render(IslandTraysSettings(initialTab:1),name:"trays-closed-"+suffix,width:570,height:650,scheme:scheme,to:folder,defaults:defaults)
   for question in [true,false] {
    let e=event(question:question);bridge.events=[e]
    try render(IslandPluginActivityView(event:e,bridge:bridge).padding(24),name:(question ? "plugin-question-" : "plugin-progress-")+suffix,width:560,height:420,scheme:scheme,to:folder,defaults:defaults)
   }
  }
 }
 @MainActor static func render<V:View>(_ view:V,name:String,width:CGFloat,height:CGFloat,scheme:ColorScheme,to folder:URL,defaults:UserDefaults) throws {
  let hosting=NSHostingView(rootView:view.defaultAppStorage(defaults).environment(\.colorScheme,scheme).frame(width:width,height:height).background(scheme == .dark ? Color(white:0.12) : Color(white:0.97)))
  hosting.frame=CGRect(x:0,y:0,width:width,height:height);hosting.layoutSubtreeIfNeeded()
  guard let image=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
  hosting.cacheDisplay(in:hosting.bounds,to:image)
  guard let bytes=image.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
  try bytes.write(to:folder.appendingPathComponent(name+".png"));print("Rendered "+name+" from production views; sample data and inert actions only")
 }
}
