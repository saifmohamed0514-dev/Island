import AppKit
import SwiftUI
import EventKit
@main struct AlcoveFeaturesRender {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  fixtureDefaults.removePersistentDomain(forName:"IslandFeaturesRender.Fixture");defer { fixtureDefaults.removePersistentDomain(forName:"IslandFeaturesRender.Fixture") }
  let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),agenda=IslandAgenda.shared
  let calendar=EKCalendar(for:.event,eventStore:agenda.store);calendar.title="Sample calendar";agenda.fixtureCalendars=[calendar]
  for (title,offset) in [("Design review",1),("Lunch with a friend",3),("A longer event name to check safe spacing",5)] {
   let event=EKEvent(eventStore:agenda.store);event.title=title;event.calendar=calendar;event.startDate=Calendar.current.date(bySettingHour:12+offset,minute:0,second:0,of:Date())!;event.endDate=event.startDate.addingTimeInterval(3600);agenda.events.append(event)
  }
  agenda.monthEvents=agenda.events
  for scheme in [ColorScheme.light,.dark] {
   let suffix=scheme == .light ? "light" : "dark"
   try render(IslandAppearanceSettings(),name:"appearance-"+suffix,width:570,height:720,scheme:scheme,to:folder)
   try render(IslandCalendarBoard(month:.constant(Date()),day:.constant(Date()),large:false,onExpand:{}).padding(12).background(.black).environment(\.colorScheme,.dark),name:"calendar-compact-"+suffix,width:640,height:150,scheme:scheme,to:folder)
   try render(IslandCalendarBoard(month:.constant(Date()),day:.constant(Date()),large:true,onExpand:{}).padding(20),name:"calendar-expanded-"+suffix,width:650,height:440,scheme:scheme,to:folder)
   try render(IslandCalendarSettings(),name:"calendar-settings-"+suffix,width:570,height:720,scheme:scheme,to:folder)
   try render(IslandLockWidgetsSettings(),name:"lock-settings-"+suffix,width:570,height:720,scheme:scheme,to:folder)
   MusicManager.shared.isPlayerIdle=false
   try render(IslandLockWidgetsView(),name:"lock-widgets-"+suffix,width:690,height:420,scheme:scheme,to:folder)
   MusicManager.shared.isPlayerIdle=false
   try render(IslandNowPlayingView().padding(20).background(.black).environment(\.colorScheme,.dark),name:"player-active-"+suffix,width:640,height:174,scheme:scheme,to:folder)
   MusicManager.shared.isPlayerIdle=true
   try render(IslandNowPlayingView().padding(20).background(.black).environment(\.colorScheme,.dark),name:"player-idle-"+suffix,width:640,height:174,scheme:scheme,to:folder)
  }
 }
 @MainActor static func render<V:View>(_ view:V,name:String,width:CGFloat,height:CGFloat,scheme:ColorScheme,to folder:URL) throws {
  let hosting=NSHostingView(rootView:view.defaultAppStorage(fixtureDefaults).environment(\.colorScheme,scheme).frame(width:width,height:height).background(scheme == .dark ? Color(white:0.12) : Color(white:0.97)))
  hosting.appearance=NSAppearance(named:scheme == .dark ? .darkAqua : .aqua)
  hosting.frame=CGRect(x:0,y:0,width:width,height:height);hosting.layoutSubtreeIfNeeded()
  guard let bitmap=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { throw CocoaError(.fileWriteUnknown) };hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
  guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) };try data.write(to:folder.appendingPathComponent(name+".png"));print("Rendered "+name+" from production views; sample data, inert actions, private defaults")
 }
}
