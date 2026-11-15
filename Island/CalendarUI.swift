import SwiftUI
import AppKit
import EventKit

struct IslandCalendarView:View {
    @EnvironmentObject private var vm:IslandViewModel
    @ObservedObject private var agenda=IslandAgenda.shared
    @ObservedObject private var settings=IslandCalendarStore.shared
    @State private var month=Date()
    @State private var day=Date()
    @State private var expanded=false
    var body:some View {
        IslandCalendarBoard(month:$month,day:$day,large:false,onExpand:{ expanded=true })
            .popover(isPresented:$expanded,arrowEdge:.bottom) {
                VStack(spacing:12) {
                    HStack { Text("Calendar").font(.headline);Spacer();Button("Today") { month=Date();day=Date() };Button("Done") { expanded=false }.keyboardShortcut(.cancelAction) }
                    IslandCalendarBoard(month:$month,day:$day,large:true,onExpand:{})
                }.padding(20).frame(width:650,height:440)
            }
            .onChange(of:expanded) { vm.isBatteryPopoverActive=expanded }
            .onHover { vm.isHoveringCalendar=$0 }
            .onDisappear { vm.isHoveringCalendar=false;vm.isBatteryPopoverActive=false }
    }
}
struct IslandCalendarBoard:View {
    @Binding var month:Date
    @Binding var day:Date
    var large:Bool
    var onExpand:()->Void
    @ObservedObject private var agenda=IslandAgenda.shared
    @ObservedObject private var settings=IslandCalendarStore.shared
    @ObservedObject private var weather=IslandWeather.shared
    @State private var selected:EKEvent?
    @State private var query=""
    @AppStorage("island.weather.fahrenheit") private var fahrenheit=false
    private var p:IslandCalendarPreferences { settings.preferences }
    private var days:[Date] { IslandCalendarRules.monthDays(month) }
    private var events:[EKEvent] { settings.visible(agenda.monthEvents) }
    private var dayEvents:[EKEvent] {
        events.filter { event in
            guard let item=IslandCalendarItem(event),IslandCalendarRules.occurs(item,on:day) else { return false }
            return query.isEmpty || [event.title ?? "",event.location ?? ""].joined(separator:" ").localizedCaseInsensitiveContains(query)
        }.sorted { $0.isAllDay != $1.isAllDay ? $0.isAllDay : $0.startDate<$1.startDate }
    }
    var body:some View {
        HStack(alignment:.top,spacing:16) {
            monthView.frame(width:p.showList ? (large ? 280 : 260) : (large ? 610 : 600))
            if p.showList { eventList.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading) }
        }
        .task(id:Calendar.current.dateInterval(of:.month,for:month)?.start) { await agenda.refreshMonth(containing:month) }
        .onReceive(NotificationCenter.default.publisher(for:.EKEventStoreChanged,object:agenda.store)) { _ in selected=nil;Task { await agenda.refreshMonth(containing:month,force:true) } }
        .onChange(of:agenda.calendarConnected) { selected=nil;if agenda.calendarConnected { Task { await agenda.refreshMonth(containing:month,force:true) } } }
        .onChange(of:day) { selected=nil }
    }
    private var monthView:some View {
        VStack(spacing:large ? 7 : 2) {
            HStack(spacing:8) {
                Button { moveMonth(-1) } label:{ Image(systemName:"chevron.left").frame(width:18,height:20) }.accessibilityLabel("Previous month")
                Button { settings.open(date:day) } label: { Text(month,format:.dateTime.month(.wide).year()).font(large ? .headline : .caption.weight(.semibold)).lineLimit(1) }.help("Open your calendar app")
                Spacer(minLength:0)
                Button { moveMonth(1) } label:{ Image(systemName:"chevron.right").frame(width:18,height:20) }.accessibilityLabel("Next month")
                if !large { Button(action:onExpand) { Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:18,height:20) }.accessibilityLabel("Expand calendar") }
            }.buttonStyle(.plain)
            if p.lunarDate { Text(settings.lunar(day)).font(.system(size:large ? 11 : 9)).foregroundStyle(.secondary).lineLimit(1) }
            weekdayLabels
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:1),count:7),spacing:large ? 3 : 1) { ForEach(days,id:\.self) { date in dateCell(date) } }
            if large { Button("Today") { month=Date();day=Date() }.buttonStyle(.bordered) }
        }
    }
    private var weekdayLabels:some View {
        let calendar=Calendar.current,symbols=calendar.veryShortStandaloneWeekdaySymbols
        return HStack(spacing:1) { ForEach(0..<7,id:\.self) { i in Text(symbols[(i+calendar.firstWeekday-1)%7]).font(.system(size:large ? 11 : 8,weight:.medium)).foregroundStyle(.secondary).frame(maxWidth:.infinity) } }
    }
    private func dateCell(_ date:Date)->some View {
        let calendar=Calendar.current,isSelected=calendar.isDate(date,inSameDayAs:day)
        let matches=events.filter { event in IslandCalendarItem(event).map { IslandCalendarRules.occurs($0,on:date) } ?? false }
        return Button {
            day=date
            if !calendar.isDate(date,equalTo:month,toGranularity:.month) { month=date }
            IslandHaptics.play(.selection)
        } label: {
            VStack(spacing:0) {
                Text("\(calendar.component(.day,from:date))").font(.system(size:large ? 12 : 10,weight:calendar.isDateInToday(date) ? .bold : .regular))
                HStack(spacing:1) { ForEach(Array(matches.prefix(3).enumerated()),id:\.offset) { _,event in Circle().fill(color(event)).frame(width:2,height:2) } }.frame(height:3)
            }.frame(maxWidth:.infinity).frame(height:large ? 24 : 14)
            .background(isSelected ? Color.accentColor.opacity(0.24) : .clear,in:RoundedRectangle(cornerRadius:5))
            .opacity(calendar.isDate(date,equalTo:month,toGranularity:.month) ? 1 : 0.4)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(date.formatted(date:.complete,time:.omitted)+", \(matches.count) events")
    }
    private var eventList:some View {
        VStack(alignment:.leading,spacing:large ? 10 : 5) {
            HStack { Text(day,format:.dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.caption.weight(.semibold));Spacer();Button { Task { await agenda.refreshMonth(containing:month,force:true);await agenda.refresh() } } label:{ Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("Refresh calendar") }
            if large { TextField("Find an event",text:$query).textFieldStyle(.roundedBorder) }
            if !agenda.calendarConnected { Text("Connect Calendar to see events.").font(.caption).foregroundStyle(.secondary);Button("Set up Calendar…") { IslandSettingsController.shared.showPermissions(.calendar) } }
            else if let selected,large { eventDetails(selected) }
            else if dayEvents.isEmpty { emptyDay }
            else { ScrollView { VStack(spacing:large ? 9 : 4) { ForEach(dayEvents.compactMap { CalendarEntry($0) }) { entry in eventRow(entry.event) } } } }
            if let message=settings.message { Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
    private var emptyDay:some View {
        VStack(alignment:.leading,spacing:6) {
            Text(query.isEmpty ? "A little space in your day." : "No matching events.").font(.caption).foregroundStyle(.secondary)
            if p.weatherWhenEmpty,let current=weather.forecast?.current { HStack { Image(systemName:"cloud.sun.fill").foregroundStyle(.orange);Text(IslandWeather.condition(current.weather_code));Text("\(Int((fahrenheit ? current.temperature_2m*9/5+32 : current.temperature_2m).rounded()))°\(fahrenheit ? "F" : "C")") }.font(.caption) }
        }.frame(maxHeight:.infinity,alignment:.top)
    }
    private func eventRow(_ event:EKEvent)->some View {
        HStack(spacing:7) {
            RoundedRectangle(cornerRadius:2).fill(color(event)).frame(width:3)
            Button {
                if large { selected=event } else { settings.open(date:day,event:event) }
            } label: {
                VStack(alignment:.leading,spacing:2) { Text(event.title ?? "Event").font(large ? .callout : .caption).lineLimit(1);Text(event.isAllDay ? "All day" : segment(event)).font(.system(size:large ? 11 : 9)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
            }.buttonStyle(.plain)
            if let url=IslandCalendarRules.meetingURL(in:event.notes ?? "",provided:event.url) { Link(destination:url) { Image(systemName:"video.fill") }.accessibilityLabel("Join "+(event.title ?? "meeting")) }
        }.frame(minHeight:large ? 38 : 24)
        .contextMenu { Button("Open in calendar") { settings.open(date:day,event:event) };Button("Hide from live activity") { settings.hide(event) } }
    }
    private func eventDetails(_ event:EKEvent)->some View {
        ScrollView { VStack(alignment:.leading,spacing:12) {
            Button("Back to events") { selected=nil }.buttonStyle(.plain)
            Text(event.title ?? "Event").font(.title3.weight(.semibold)).textSelection(.enabled)
            Text(event.isAllDay ? "All day" : segment(event)).foregroundStyle(.secondary)
            if let location=event.location,!location.isEmpty {
                Text(location).font(.callout).textSelection(.enabled)
                if let url=IslandCalendarRules.mapsURL(location) { Link("Directions in Maps",destination:url) }
            }
            if let notes=event.notes,!notes.isEmpty { Text(String(notes.prefix(8000))).font(.callout).textSelection(.enabled) }
            if let url=IslandCalendarRules.meetingURL(in:event.notes ?? "",provided:event.url) { Link("Join meeting",destination:url).buttonStyle(.borderedProminent) }
            Button("Open in calendar") { settings.open(date:day,event:event) }
            Button("Hide from live activity") { settings.hide(event) }
        } }
    }
    private func color(_ event:EKEvent)->Color { guard p.showCalendarColors,let calendar=event.calendar,let color=calendar.cgColor else { return .accentColor };return Color(cgColor:color) }
    private func segment(_ event:EKEvent)->String {
        let start=Calendar.current.startOfDay(for:day),next=Calendar.current.date(byAdding:.day,value:1,to:start) ?? start.addingTimeInterval(86400)
        return max(start,event.startDate).formatted(date:.omitted,time:.shortened)+" – "+min(next,event.endDate).formatted(date:.omitted,time:.shortened)
    }
    private func moveMonth(_ delta:Int) {
        if let date=Calendar.current.date(byAdding:.month,value:delta,to:month) { month=date;day=Calendar.current.dateInterval(of:.month,for:date)?.start ?? date;selected=nil;IslandHaptics.play(.selection) }
    }
}

private struct CalendarEntry:Identifiable {
 let event:EKEvent
 let id:String
 init?(_ event:EKEvent) { guard let item=IslandCalendarItem(event) else { return nil };self.event=event;id=item.occurrenceID }
}
