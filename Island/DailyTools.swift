import SwiftUI
import Combine
import EventKit
import AppKit

struct IslandHealthView: View {
    @AppStorage("island.health.day") var day = ""
    @AppStorage("island.health.water") var water = 0
    @AppStorage("island.health.breaks") var breaks = 0
    @AppStorage("island.health.mindful") var mindful = 0
    @AppStorage("island.health.waterGoal") var waterGoal = 8
    @AppStorage("island.health.breakGoal") var breakGoal = 6
    @AppStorage("island.health.mindfulGoal") var mindfulGoal=5
    @State var stretchSince:Date?
    @State var breathingSince: Date?
    @State var eyeBreakSince: Date?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            IslandModuleHeading(title:"Wellbeing",subtitle:"Small pauses, a better day")
            HStack(spacing:25) {
                healthRing("Water",current:water,goal:max(1,waterGoal),color:.cyan)
                healthRing("Breaks",current:breaks,goal:max(1,breakGoal),color:.green)
                healthRing("Mindful",current:mindful,goal:max(1,mindfulGoal),color:.purple)
                VStack(alignment:.leading,spacing:7) {
                    HStack { Button("− Water") { IslandHaptics.play(.selection);water = max(0,water-1) }; Button("+ Water") { IslandHaptics.play(.confirmation);water += 1 } }
                    HStack { Button("Stretch break") { stretchSince=Date() }; Button("Eye break") { eyeBreakSince = Date() } }
                    Button(breathingSince == nil ? "Start breathing" : "Finish breathing") { if breathingSince == nil { breathingSince = Date() } else { mindful += 1; breathingSince = nil } }
                }.buttonStyle(.bordered)
            }
            if let start=stretchSince {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let remaining=max(0,60-Int(context.date.timeIntervalSince(start)))
                    HStack { Text(remaining > 40 ? "Relax your shoulders and unclench your hands." : remaining > 20 ? "Stand and move at a comfortable pace." : "Rest your gaze away from the screen.").font(.caption);Spacer();Text("\(remaining)s").monospacedDigit();Button(remaining == 0 ? "Finish break" : "Skip") { if remaining == 0 { breaks += 1 };stretchSince=nil } }
                }
            }
            if let start = breathingSince {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let second = Int(context.date.timeIntervalSince(start)) % 16
                    Text(second < 4 ? "Breathe in…" : second < 8 ? "Hold…" : second < 12 ? "Breathe out…" : "Rest…").foregroundStyle(.purple)
                }
            }
            if let start = eyeBreakSince {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    HStack { Text("Look about 20 feet away · \(max(0,20-Int(context.date.timeIntervalSince(start)))) seconds"); Button(Date().timeIntervalSince(start)>=20 ? "Done" : "Skip") { guard eyeBreakSince != nil else { return };eyeBreakSince = nil;if Date().timeIntervalSince(start)>=20 { breaks += 1 };IslandHaptics.play(.selection) } }
                }
            }
        }.onAppear {
            let today = Date().formatted(.iso8601.year().month().day())
            if day != today { day = today; water = 0; breaks = 0; mindful = 0 }
        }
    }
    func healthRing(_ title:String,current:Int,goal:Int,color:Color) -> some View {
        VStack(spacing:5) {
            ZStack { Circle().stroke(color.opacity(0.18),lineWidth:5); Circle().trim(from:0,to:min(1,Double(current)/Double(goal))).stroke(color,style:StrokeStyle(lineWidth:5,lineCap:.round)).rotationEffect(.degrees(-90)); Text("\(current)").font(.headline) }.frame(width:43,height:43)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor final class IslandAgenda: ObservableObject {
    static let shared = IslandAgenda()
    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var reminders: [EKReminder] = []
    @Published var error: String?
    @Published var loading = false
    @Published var calendarConnected = EKEventStore.authorizationStatus(for:.event) == .fullAccess
    @Published var remindersConnected = EKEventStore.authorizationStatus(for:.reminder) == .fullAccess
    struct Trashed: Codable,Identifiable { var id: String; var title: String; var listID: String; var completed: Bool; var removed: Date; var due: DateComponents? }
    @Published var trash: [Trashed] = []
    private init() {
        if let data = UserDefaults.standard.data(forKey:"island.tasks.trash"), let saved = try? JSONDecoder().decode([Trashed].self,from:data) { trash = saved.filter { Date().timeIntervalSince($0.removed) < 30 * 86400 } }
    }
    func connect(events:Bool) async {
        do {
            if events { calendarConnected = try await store.requestFullAccessToEvents() }
            else { remindersConnected = try await store.requestFullAccessToReminders() }
            await refresh()
        } catch { self.error = "Access wasn’t granted. You can review permissions in System Settings." }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        calendarConnected = EKEventStore.authorizationStatus(for:.event) == .fullAccess
        remindersConnected = EKEventStore.authorizationStatus(for:.reminder) == .fullAccess
        if calendarConnected {
            let now = Calendar.current.startOfDay(for:Date())
            events = store.events(matching:store.predicateForEvents(withStart:now,end:now.addingTimeInterval(7*86400),calendars:nil)).sorted { $0.startDate < $1.startDate }
        }
        if remindersConnected {
            let predicate = store.predicateForReminders(in:nil)
            reminders = await withCheckedContinuation { continuation in store.fetchReminders(matching:predicate) { continuation.resume(returning:$0 ?? []) } }
            reminders.sort { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
        }
    }
    func add(_ text:String) async {
        let title = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let calendar = store.defaultCalendarForNewReminders() else { error = "Create a writable reminder list in Reminders first."; return }
        let reminder = EKReminder(eventStore:store); reminder.title = title; reminder.calendar = calendar
        do { try store.save(reminder,commit:true); error = nil; await refresh() } catch { self.error = "Couldn’t save this task." }
    }
    func toggle(_ reminder:EKReminder) async {
        reminder.isCompleted.toggle()
        do { try store.save(reminder,commit:true); await refresh() } catch { reminder.isCompleted.toggle(); self.error = "Couldn’t update this task." }
    }
    func remove(_ reminder:EKReminder) async {
        let copy = Trashed(id:UUID().uuidString,title:reminder.title ?? "Task",listID:reminder.calendar.calendarIdentifier,completed:reminder.isCompleted,removed:Date(),due:reminder.dueDateComponents)
        do { try store.remove(reminder,commit:true); trash.append(copy); saveTrash(); await refresh() } catch { self.error = "Couldn’t move this task to trash." }
    }
    func restore(_ item:Trashed) async {
        guard let calendar = store.calendar(withIdentifier:item.listID) ?? store.defaultCalendarForNewReminders() else { error = "No writable reminders list."; return }
        let reminder = EKReminder(eventStore:store); reminder.title = item.title; reminder.calendar = calendar; reminder.isCompleted = item.completed; reminder.dueDateComponents = item.due
        do { try store.save(reminder,commit:true); trash.removeAll { $0.id == item.id }; saveTrash(); await refresh() } catch { self.error = "Couldn’t restore this task." }
    }
    private func saveTrash() { UserDefaults.standard.set(try? JSONEncoder().encode(trash),forKey:"island.tasks.trash") }
}
struct IslandAgendaView: View {
    @ObservedObject var agenda = IslandAgenda.shared
    @State var query = ""
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { TextField("Search calendar",text:$query).textFieldStyle(.roundedBorder); Button("Refresh") { Task { await agenda.refresh() } } }
            if !agenda.calendarConnected { Button("Set up Calendar…") { IslandSettingsController.shared.showPermissions(.calendar) } }
            ForEach(agenda.events.filter { query.isEmpty || [ $0.title ?? "", $0.location ?? "", $0.notes ?? "", $0.calendar.title ].joined(separator:" ").localizedCaseInsensitiveContains(query) },id:\.calendarItemIdentifier) { event in
                HStack { Text(event.startDate,style:.time).monospacedDigit().foregroundStyle(.secondary); Text(event.title ?? "Event"); Spacer(); if let url = event.url { Link("Open",destination:url) } }
            }
            if agenda.calendarConnected && agenda.events.isEmpty { Text("No upcoming events this week.").foregroundStyle(.secondary) }
            if let error = agenda.error { Text(error).foregroundStyle(.orange) }
        }.task { await agenda.refresh() }
    }
}
struct IslandTasksView: View {
    @ObservedObject var agenda = IslandAgenda.shared
    @State var text = ""
    @State var completed = false
    @State var trash = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if !agenda.remindersConnected { Button("Set up Reminders…") { IslandSettingsController.shared.showPermissions(.reminders) } }
            HStack { TextField("Add a task",text:$text).textFieldStyle(.roundedBorder).onSubmit { add() }; Button("Add") { add() }.disabled(text.trimmingCharacters(in:.whitespaces).isEmpty || !agenda.remindersConnected); Toggle("Completed",isOn:$completed).toggleStyle(.checkbox); Toggle("Trash",isOn:$trash).toggleStyle(.checkbox) }
            if trash {
                Text("Tasks remain recoverable here for 30 days.").font(.caption).foregroundStyle(.secondary)
                ForEach(agenda.trash) { item in HStack { Text(item.title); Spacer(); Button("Restore") { Task { await agenda.restore(item) } } } }
            } else {
                ForEach(agenda.reminders.filter { completed || !$0.isCompleted },id:\.calendarItemIdentifier) { reminder in
                    HStack {
                        Button { Task { await agenda.toggle(reminder) } } label: { Image(systemName:reminder.isCompleted ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain).accessibilityLabel("Toggle \(reminder.title ?? "task")")
                        Text(reminder.title ?? "Task").strikethrough(reminder.isCompleted); Spacer()
                        Button { Task { await agenda.remove(reminder) } } label: { Image(systemName:"trash") }.buttonStyle(.plain).help("Move task to recoverable trash")
                    }
                }
            }
            if let error = agenda.error { Text(error).foregroundStyle(.orange) }
        }.task { await agenda.refresh() }
    }
    func add() { let title = text; text = ""; Task { await agenda.add(title) } }
}
struct IslandDayView:View {
    @ObservedObject var agenda=IslandAgenda.shared
    @AppStorage("island.day.events") private var showEvents=true
    @AppStorage("island.day.tasks") private var showTasks=true
    @AppStorage("island.day.bedtime") private var bedtime=false
    @AppStorage("island.day.bedtimeMinute") private var bedtimeMinute=1320
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) { context in
            let start=Calendar.current.startOfDay(for:context.date),next=Calendar.current.date(byAdding:.day,value:1,to:start) ?? start.addingTimeInterval(86400)
            let progress=min(1,max(0,context.date.timeIntervalSince(start)/next.timeIntervalSince(start)))
            VStack(alignment:.leading,spacing:10) {
                HStack { Text("Today").font(.headline);Spacer();Text("\(Int(progress*100))% of the day").foregroundStyle(.secondary) }
                ProgressView(value:progress).tint(.orange)
                if showEvents {
                    ForEach(agenda.events.filter { Calendar.current.isDate($0.startDate,inSameDayAs:context.date) },id:\.calendarItemIdentifier) { event in HStack { Image(systemName:"calendar").foregroundStyle(.cyan);Text(event.startDate,style:.time).monospacedDigit();Text(event.title ?? "Event");Spacer();if event.startDate<=context.date && event.endDate>context.date { Text("Now").font(.caption).foregroundStyle(.cyan) } }.font(.callout) }
                    if !agenda.calendarConnected { Button("Connect Calendar…") { IslandSettingsController.shared.showPermissions(.calendar) } }
                }
                if showTasks {
                    ForEach(agenda.reminders.filter { !$0.isCompleted && $0.dueDateComponents.flatMap { Calendar.current.date(from:$0) }.map { $0<next } == true },id:\.calendarItemIdentifier) { reminder in HStack { Button { IslandHaptics.play(.confirmation);Task { await agenda.toggle(reminder) } } label: { Image(systemName:"circle") }.buttonStyle(.plain).accessibilityLabel("Complete "+(reminder.title ?? "task"));Text(reminder.title ?? "Task");Spacer();if let due=reminder.dueDateComponents.flatMap({ Calendar.current.date(from:$0) }) { Text(due<start ? "Overdue" : due.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(due<start ? .orange : .secondary) } } }
                    if !agenda.remindersConnected { Button("Connect Reminders…") { IslandSettingsController.shared.showPermissions(.reminders) } }
                }
                if bedtime { Label("Wind down at "+String(format:"%02d:%02d",bedtimeMinute/60,bedtimeMinute%60),systemImage:"moon").font(.caption).foregroundStyle(.secondary) }
                if !showEvents && !showTasks { Text("Choose timeline sources in this module’s settings.").font(.caption).foregroundStyle(.secondary) }
            }
        }.task { await agenda.refresh() }
    }
}
struct IslandDaySettings:View {
    @AppStorage("island.day.events") private var events=true
    @AppStorage("island.day.tasks") private var tasks=true
    @AppStorage("island.day.bedtime") private var bedtime=false
    @AppStorage("island.day.bedtimeMinute") private var minute=1320
    var body:some View { Form {
        Section("Today’s timeline") { Toggle("Show calendar events",isOn:$events);Toggle("Show due and overdue tasks",isOn:$tasks);Button("Manage Calendar and Reminders access…") { IslandSettingsController.shared.showPermissions(events ? .calendar : .reminders) } }
        Section("Evening") { Toggle("Show a wind-down marker",isOn:$bedtime);DatePicker("Wind down",selection:Binding(get:{ Calendar.current.date(bySettingHour:minute/60,minute:minute%60,second:0,of:Date()) ?? Date() },set:{ minute=Calendar.current.component(.hour,from:$0)*60+Calendar.current.component(.minute,from:$0) }),displayedComponents:.hourAndMinute).disabled(!bedtime) }
    }.formStyle(.grouped) }
}

struct IslandLauncherView: View {
    struct Item: Codable,Identifiable { var id: String; var title: String; var bookmark: Data }
    @State var items: [Item] = []
    @State var error: String?
    @AppStorage("island.launcher.style") private var style="grid"
    @AppStorage("island.launcher.shortcuts") private var shortcutData=Data()
    @State private var shortcutName=""
    private var shortcutNames:[String] { (try? JSONDecoder().decode([String].self,from:shortcutData)) ?? [] }
    private func runShortcut(_ name:String) {
        var url=URLComponents();url.scheme="shortcuts";url.host="run-shortcut";url.queryItems=[URLQueryItem(name:"name",value:name)]
        if let url=url.url { IslandHaptics.play(.confirmation);NSWorkspace.shared.open(url) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Launcher").font(.headline); Spacer(); Button("Add app or folder…") { add() } }
            Picker("Layout",selection:$style) { Text("Grid").tag("grid");Text("List").tag("list") }.pickerStyle(.segmented).frame(width:180)
            LazyVGrid(columns:style == "list" ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum:110))],alignment:.leading,spacing:8) { ForEach(items) { item in
                Button { IslandHaptics.play(.selection);open(item) } label: { Label(item.title,systemImage:"arrow.up.right.square").frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10)) }.buttonStyle(.plain).contextMenu { Button("Remove shortcut",role:.destructive) { items.removeAll { $0.id == item.id };save() } }
            } }
            DisclosureGroup("Your Shortcuts") {
                HStack { TextField("Name of a shortcut on this Mac",text:$shortcutName).textFieldStyle(.roundedBorder);Button("Add") { let name=shortcutName.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty,name.count<=200,!shortcutNames.contains(name),shortcutNames.count<50 else { return };shortcutData=(try? JSONEncoder().encode(shortcutNames+[name])) ?? Data();shortcutName="";IslandHaptics.play(.placement) }.disabled(shortcutName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                ForEach(shortcutNames,id:\.self) { name in HStack { Button(name) { runShortcut(name) }.buttonStyle(.bordered);Spacer();Button("Remove") { shortcutData=(try? JSONEncoder().encode(shortcutNames.filter { $0 != name })) ?? Data() }.font(.caption).buttonStyle(.plain) } }
            }
            IslandQuickActionsView()
            if items.isEmpty { Text("Keep apps and folders you use close by.").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.orange) }
        }.onAppear { if let data = UserDefaults.standard.data(forKey:"island.launcher"), let saved = try? JSONDecoder().decode([Item].self,from:data) { items = saved } }
    }
    func add() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
            do { let bookmark = try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil); items.append(Item(id:UUID().uuidString,title:url.deletingPathExtension().lastPathComponent,bookmark:bookmark)) } catch { self.error = "Couldn’t save this shortcut." }
        }; save()
    }
    func open(_ item:Item) {
        do { var stale = false; let url = try URL(resolvingBookmarkData:item.bookmark,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
            let scoped = url.startAccessingSecurityScopedResource()
            NSWorkspace.shared.open(url,configuration:NSWorkspace.OpenConfiguration()) { _,_ in if scoped { url.stopAccessingSecurityScopedResource() } }
        } catch { self.error = "This shortcut is unavailable. Add it again." }
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(items),forKey:"island.launcher") }
}
