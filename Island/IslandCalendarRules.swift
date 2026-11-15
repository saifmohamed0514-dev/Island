import Foundation
import CryptoKit

struct IslandCalendarPreferences:Codable,Equatable {
    var excludedCalendars:[String]=[]
    var showDeclined=false
    var includeSubscribed=true
    var showCalendarColors=true
    var showList=true
    var lunarDate=false
    var weatherWhenEmpty=true
    var preferredApp="system"
    var activityLeadMinutes=30.0
    var allDayActivities=false
    var leaveReminders=false
    var leaveLeadMinutes=15.0
    var notificationDetails=false
    var dismissed:[String:Date]=[:]
    mutating func normalize(now:Date = .now) {
        excludedCalendars=Array(Set(excludedCalendars.filter { !$0.isEmpty && $0.utf8.count<500 }).sorted().prefix(100))
        if !["system","apple","fantastical","notion"].contains(preferredApp) { preferredApp="system" }
        activityLeadMinutes=activityLeadMinutes.isFinite ? min(1440,max(1,activityLeadMinutes)) : 30
        leaveLeadMinutes=leaveLeadMinutes.isFinite ? min(240,max(1,leaveLeadMinutes)) : 15
        dismissed=Dictionary(uniqueKeysWithValues:dismissed.filter { $0.value>now && $0.value.timeIntervalSince(now)<366*86400 && $0.key.utf8.count<800 }.sorted { $0.value>$1.value }.prefix(100).map { ($0.key,$0.value) })
    }
}
struct IslandCalendarItem:Identifiable,Equatable,Sendable {
    let id:String
    let title:String
    let start:Date
    let end:Date
    let calendarID:String
    let allDay:Bool
    let declined:Bool
    let subscribed:Bool
    var occurrenceID:String { id+":"+String(start.timeIntervalSince1970) }
}
struct IslandCalendarReminder:Identifiable,Equatable,Sendable {
    let id:String
    let fire:Date
    let body:String
}
enum IslandCalendarRules {
    static func visible(_ event:IslandCalendarItem,preferences:IslandCalendarPreferences)->Bool {
        !preferences.excludedCalendars.contains(event.calendarID) && (preferences.showDeclined || !event.declined) && (preferences.includeSubscribed || !event.subscribed)
    }
    static func occurs(_ event:IslandCalendarItem,on date:Date,calendar:Calendar = .current)->Bool {
        let start=calendar.startOfDay(for:date)
        guard let end=calendar.date(byAdding:.day,value:1,to:start) else { return false }
        return event.start<end && max(event.end,event.start.addingTimeInterval(1))>start
    }
    static func active(_ event:IslandCalendarItem,preferences:IslandCalendarPreferences,now:Date = .now)->Bool {
        visible(event,preferences:preferences) && event.end>now && event.start.timeIntervalSince(now)<=preferences.activityLeadMinutes*60 && (preferences.allDayActivities || !event.allDay) && preferences.dismissed[event.occurrenceID] == nil
    }
    static func monthDays(_ date:Date,calendar:Calendar = .current)->[Date] {
        guard let month=calendar.dateInterval(of:.month,for:date) else { return [] }
        let offset=(calendar.component(.weekday,from:month.start)-calendar.firstWeekday+7)%7
        guard let start=calendar.date(byAdding:.day,value:-offset,to:month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding:.day,value:$0,to:start) }
    }
    static func reminders(_ events:[IslandCalendarItem],preferences:IslandCalendarPreferences,now:Date = .now)->[IslandCalendarReminder] {
        guard preferences.leaveReminders else { return [] }
        var seen=Set<String>()
        return events.sorted { $0.start<$1.start }.compactMap { event in
            guard visible(event,preferences:preferences),!event.declined,!event.allDay,preferences.dismissed[event.occurrenceID] == nil,seen.insert(event.occurrenceID).inserted else { return nil }
            let fire=event.start.addingTimeInterval(-preferences.leaveLeadMinutes*60)
            guard fire>now,fire.timeIntervalSince(now)<7*86400 else { return nil }
            let digest=SHA256.hash(data:Data(event.occurrenceID.utf8)).map { String(format:"%02x",$0) }.joined()
            return IslandCalendarReminder(id:"IslandCalendarLeave-"+String(digest.prefix(32)),fire:fire,body:preferences.notificationDetails ? String(event.title.prefix(300)) : "Your next event starts soon.")
        }.prefix(16).map { $0 }
    }
    static func mapsURL(_ address:String)->URL? {
        guard !address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        var components=URLComponents(string:"https://maps.apple.com/")
        components?.queryItems=[URLQueryItem(name:"daddr",value:address)]
        return components?.url
    }
    static func meetingURL(in text:String,provided:URL?=nil)->URL? {
        let hosts=["zoom.us","zoom.com","teams.microsoft.com","teams.live.com","meet.google.com","webex.com","whereby.com","facetime.apple.com","meet.jit.si"]
        func accepted(_ url:URL)->Bool {
            guard url.scheme?.lowercased()=="https",let host=url.host?.lowercased() else { return false }
            return hosts.contains { host==$0 || host.hasSuffix("."+$0) }
        }
        if let provided,accepted(provided) { return provided }
        guard let detector=try? NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let bounded=String(text.prefix(20000))
        return detector.matches(in:bounded,range:NSRange(bounded.startIndex...,in:bounded)).compactMap(\.url).first(where:accepted)
    }
}
