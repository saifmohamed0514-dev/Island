import Foundation
@main struct CalendarSmoke {
 @MainActor static func main() async {
  var count=0
  func check(_ value:Bool) { precondition(value,"Calendar check \(count+1)");count+=1 }
  var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"America/Los_Angeles")!;calendar.firstWeekday=2
  func date(_ day:Int,_ hour:Int=0)->Date { calendar.date(from:DateComponents(year:2026,month:3,day:day,hour:hour))! }
  let days=IslandCalendarRules.monthDays(date(8),calendar:calendar)
  check(days.count==42 && calendar.component(.weekday,from:days[0])==2)
  check(Set(days).count==42)
  let index=days.firstIndex(of:date(8))!;check(days[index+1].timeIntervalSince(days[index])==23*3600)
  func item(_ id:String="item",_ start:Date?=nil,_ end:Date?=nil,_ allDay:Bool=false,_ declined:Bool=false,_ subscribed:Bool=false)->IslandCalendarItem { .init(id:id,title:"Fixture meeting",start:start ?? date(8,10),end:end ?? date(8,11),calendarID:"calendar",allDay:allDay,declined:declined,subscribed:subscribed) }
  var p=IslandCalendarPreferences()
  check(IslandCalendarRules.occurs(item(),on:date(8),calendar:calendar))
  check(!IslandCalendarRules.occurs(item(),on:date(9),calendar:calendar))
  let spanning=item("span",date(7,21),date(9))
  check(IslandCalendarRules.occurs(spanning,on:date(8),calendar:calendar))
  check(!IslandCalendarRules.occurs(spanning,on:date(9),calendar:calendar))
  check(!IslandCalendarRules.visible(item("declined",nil,nil,false,true),preferences:p))
  p.showDeclined=true;check(IslandCalendarRules.visible(item("declined",nil,nil,false,true),preferences:p))
  p.includeSubscribed=false;check(!IslandCalendarRules.visible(item("sub",nil,nil,false,false,true),preferences:p))
  p.excludedCalendars=["calendar"];check(!IslandCalendarRules.visible(item(),preferences:p));p.excludedCalendars=[]
  check(IslandCalendarRules.active(item(),preferences:p,now:date(8,10)))
  check(!IslandCalendarRules.active(item(),preferences:p,now:date(8,9)))
  check(!IslandCalendarRules.active(item(),preferences:p,now:date(8,11)))
  check(!IslandCalendarRules.active(item("all",nil,nil,true),preferences:p,now:date(8,10)))
  p.allDayActivities=true;check(IslandCalendarRules.active(item("all",nil,nil,true),preferences:p,now:date(8,10)))
  p.dismissed[item().occurrenceID]=date(8,11);check(!IslandCalendarRules.active(item(),preferences:p,now:date(8,10)))
  check(item("repeat",date(8,10)).occurrenceID != item("repeat",date(9,10)).occurrenceID)
  p.dismissed=[:];p.leaveReminders=true
  let plan=IslandCalendarRules.reminders([item(),item(),item("declined",nil,nil,false,true),item("all",nil,nil,true)],preferences:p,now:date(8,9))
  check(plan.count==1 && plan[0].fire==date(8,10).addingTimeInterval(-900))
  check(!plan[0].body.contains("Fixture"))
  p.notificationDetails=true;check(IslandCalendarRules.reminders([item()],preferences:p,now:date(8,9))[0].body=="Fixture meeting")
  check(IslandCalendarRules.reminders([item()],preferences:p,now:date(8,10)).isEmpty)
  p.leaveReminders=false;check(IslandCalendarRules.reminders([item()],preferences:p,now:date(8,9)).isEmpty)
  p.activityLeadMinutes = .nan;p.leaveLeadMinutes = .infinity;p.preferredApp="bad";p.dismissed=["expired":date(1)];p.normalize(now:date(8))
  check(p.activityLeadMinutes==30 && p.leaveLeadMinutes==15 && p.preferredApp=="system" && p.dismissed.isEmpty)
  check(IslandCalendarRules.meetingURL(in:"Visit https://zoom.us/j/123")?.host=="zoom.us")
  check(IslandCalendarRules.meetingURL(in:"Visit https://zoom.us.evil.test/j/123")==nil)
  check(IslandCalendarRules.meetingURL(in:"http://zoom.us/j/123")==nil)
  check(IslandCalendarRules.meetingURL(in:"https://teams.microsoft.com/l/meetup-join/abc") != nil)
  let address="R&D Square & ll=123"
  check(URLComponents(url:IslandCalendarRules.mapsURL(address)!,resolvingAgainstBaseURL:false)?.queryItems?.first?.value==address)
  let suite="IslandCalendarTests."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  defaults.set("kept",forKey:"island.notes")
  let store=IslandCalendarStore(defaults:defaults);store.set(\.preferredApp,"notion");store.toggleCalendar("hidden",enabled:false)
  check(IslandCalendarStore(defaults:defaults).preferences.excludedCalendars==["hidden"])
  check(IslandCalendarStore(defaults:defaults).preferences.preferredApp=="notion")
  check(defaults.string(forKey:"island.notes")=="kept")
  let center=UNUserNotificationCenter.current();center.reset();center.holdNextAdd=true
  let now=Date(),a=IslandCalendarItem(id:"A",title:"A",start:now.addingTimeInterval(7200),end:now.addingTimeInterval(10800),calendarID:"calendar",allDay:false,declined:false,subscribed:false),b=IslandCalendarItem(id:"B",title:"B",start:now.addingTimeInterval(14400),end:now.addingTimeInterval(18000),calendarID:"calendar",allDay:false,declined:false,subscribed:false)
  var alerts=IslandCalendarPreferences();alerts.leaveReminders=true
  let scheduler=IslandCalendarAlerts();scheduler.configure([a],preferences:alerts)
  await center.waitUntilHeld()
  var disabled=alerts;disabled.leaveReminders=false
  scheduler.configure([],preferences:disabled);scheduler.configure([b],preferences:alerts)
  check(center.added.isEmpty)
  center.releaseHeldAdd();await scheduler.task?.value
  let bID=IslandCalendarRules.reminders([b],preferences:alerts)[0].id
  check(Set(center.pending.map(\.identifier))==Set(["foreign-timer",bID]))
  scheduler.configure([],preferences:disabled);await scheduler.task?.value
  check(center.pending.map(\.identifier)==["foreign-timer"])
  center.authorization = .denied;scheduler.configure([a],preferences:alerts);await scheduler.task?.value
  check(center.pending.map(\.identifier)==["foreign-timer"])
  print("PASS: \(count) production calendar/alert checks; DST grids, multi-day boundaries, filters, recurring IDs, privacy, safe meeting/maps URLs, private persistence and serialized late-add/disable/replace behavior; native center substituted")
 }
}
