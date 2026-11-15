import SwiftUI
import AppKit
import EventKit

extension IslandCalendarItem {
    init?(_ event:EKEvent) {
        guard let start=event.startDate,let end=event.endDate,let calendar=event.calendar,start.timeIntervalSince1970.isFinite,end.timeIntervalSince1970.isFinite else { return nil }
        self.init(id:event.calendarItemIdentifier,title:event.title ?? "Event",start:start,end:end,calendarID:calendar.calendarIdentifier,allDay:event.isAllDay,declined:event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,subscribed:calendar.type == .subscription)
    }
}
@MainActor final class IslandCalendarStore:ObservableObject {
    static let shared=IslandCalendarStore()
    @Published private(set) var preferences:IslandCalendarPreferences
    @Published var message:String?
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        var p=defaults.data(forKey:"island.calendar.preferences").flatMap { try? JSONDecoder().decode(IslandCalendarPreferences.self,from:$0) } ?? IslandCalendarPreferences()
        p.normalize();preferences=p
    }
    func set<T>(_ path:WritableKeyPath<IslandCalendarPreferences,T>,_ value:T) {
        var p=preferences;p[keyPath:path]=value;p.normalize();guard p != preferences else { return }
        preferences=p;defaults.set(try? JSONEncoder().encode(p),forKey:"island.calendar.preferences")
        NotificationCenter.default.post(name:Notification.Name("IslandCalendarPreferencesChanged"),object:nil)
    }
    func binding<T>(_ path:WritableKeyPath<IslandCalendarPreferences,T>)->Binding<T> { Binding(get:{ self.preferences[keyPath:path] },set:{ self.set(path,$0) }) }
    func visible(_ events:[EKEvent])->[EKEvent] { events.filter { IslandCalendarItem($0).map { IslandCalendarRules.visible($0,preferences:preferences) } ?? false } }
    func activity(_ events:[EKEvent],now:Date = .now)->[EKEvent] { events.filter { IslandCalendarItem($0).map { IslandCalendarRules.active($0,preferences:preferences,now:now) } ?? false } }
    func hide(_ event:EKEvent) {
        guard let item=IslandCalendarItem(event) else { return }
        var hidden=preferences.dismissed;hidden[item.occurrenceID]=item.end;set(\.dismissed,hidden)
    }
    func toggleCalendar(_ id:String,enabled:Bool) {
        var ids=preferences.excludedCalendars.filter { $0 != id };if !enabled { ids.append(id) };set(\.excludedCalendars,ids)
    }
    func open(date:Date,event:EKEvent?=nil) {
        let workspace=NSWorkspace.shared
        if preferences.preferredApp == "fantastical" {
            let f=DateFormatter();f.calendar=Calendar(identifier:.gregorian);f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd"
            if let url=URL(string:"x-fantastical://date/"+f.string(from:date)),workspace.urlForApplication(toOpen:url) != nil,workspace.open(url) { message=nil;return }
            message="Fantastical couldn’t open. Install it or choose another calendar app.";return
        }
        let id=preferences.preferredApp == "notion" ? "com.cron.electron" : "com.apple.iCal"
        if preferences.preferredApp != "notion",let event,let identifier=event.eventIdentifier,let escaped=identifier.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed),let url=URL(string:"x-apple-calevent://"+escaped),workspace.urlForApplication(toOpen:url) != nil,workspace.open(url) { message=nil;return }
        guard let url=workspace.urlForApplication(withBundleIdentifier:id),workspace.open(url) else { message="Install or open your selected calendar app, or choose Apple Calendar.";return }
        message=nil
    }
    func lunar(_ date:Date)->String {
        let f=DateFormatter();f.calendar=Calendar(identifier:.chinese);f.locale = .current;f.setLocalizedDateFormatFromTemplate("U MMMd");return f.string(from:date)
    }
}
struct IslandCalendarSettings:View {
    @ObservedObject private var model=IslandCalendarStore.shared
    @ObservedObject private var agenda=IslandAgenda.shared
    @ObservedObject private var alerts=IslandCalendarAlerts.shared
    var body:some View {
        Form {
            Section("Your calendar") {
                Button("Manage Calendar access…") { IslandSettingsController.shared.showPermissions(.calendar) }
                Picker("Open events with",selection:model.binding(\.preferredApp)) { Text("Apple Calendar / system handler").tag("system");Text("Apple Calendar").tag("apple");Text("Fantastical").tag("fantastical");Text("Notion Calendar").tag("notion") }
                Toggle("Show calendar colors",isOn:model.binding(\.showCalendarColors))
                Toggle("Show event list",isOn:model.binding(\.showList))
                Toggle("Show Chinese lunar date and year",isOn:model.binding(\.lunarDate))
                Toggle("Show cached weather on clear days",isOn:model.binding(\.weatherWhenEmpty))
            }
            Section("Calendars and invitations") {
                Toggle("Show declined invitations",isOn:model.binding(\.showDeclined))
                Toggle("Include subscribed calendars",isOn:model.binding(\.includeSubscribed))
                if agenda.calendarConnected { ForEach(agenda.store.calendars(for:.event),id:\.calendarIdentifier) { calendar in
                    Toggle(calendar.title,isOn:Binding(get:{ !model.preferences.excludedCalendars.contains(calendar.calendarIdentifier) },set:{ model.toggleCalendar(calendar.calendarIdentifier,enabled:$0) }))
                } }
            }
            Section("Beside the camera") {
                Slider(value:model.binding(\.activityLeadMinutes),in:1...1440,step:1) { Text("Show before an event") }
                Text("\(Int(model.preferences.activityLeadMinutes)) minutes before · stays visible during the event").font(.caption).foregroundStyle(.secondary)
                Toggle("Include all-day events as live activities",isOn:model.binding(\.allDayActivities))
                Button("Restore hidden events") { model.set(\.dismissed,[:]) }.disabled(model.preferences.dismissed.isEmpty)
            }
            Section("Time to leave") {
                Toggle("Remind me before timed events",isOn:model.binding(\.leaveReminders))
                Slider(value:model.binding(\.leaveLeadMinutes),in:1...240,step:1) { Text("Lead time") }
                Text("\(Int(model.preferences.leaveLeadMinutes)) minutes before. This is your chosen lead time, not a live traffic estimate. Declined and all-day events never ring.").font(.caption).foregroundStyle(.secondary)
                Toggle("Include event titles in reminders",isOn:model.binding(\.notificationDetails))
                Button("Manage notification access…") { IslandSettingsController.shared.showPermissions(.notifications) }
                if !alerts.status.isEmpty { Text(alerts.status).font(.caption).foregroundStyle(.secondary) }
            }
            if let message=model.message { Section { Text(message).foregroundStyle(.secondary) } }
        }.formStyle(.grouped).task { await agenda.refresh() }
    }
}
