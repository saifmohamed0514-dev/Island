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
    @State var breathingSince: Date?
    @State var eyeBreakSince: Date?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            IslandModuleHeading(title:"Wellbeing",subtitle:"Small pauses, a better day")
            HStack(spacing:25) {
                healthRing("Water",current:water,goal:max(1,waterGoal),color:.cyan)
                healthRing("Breaks",current:breaks,goal:max(1,breakGoal),color:.green)
                healthRing("Mindful",current:mindful,goal:5,color:.purple)
                VStack(alignment:.leading,spacing:7) {
                    HStack { Button("− Water") { water = max(0,water-1) }; Button("+ Water") { water += 1 } }
                    HStack { Button("Movement break") { breaks += 1 }; Button("Eye break") { eyeBreakSince = Date() } }
                    Button(breathingSince == nil ? "Start breathing" : "Finish breathing") { if breathingSince == nil { breathingSince = Date() } else { mindful += 1; breathingSince = nil } }
                }.buttonStyle(.bordered)
            }
            if let start = breathingSince {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let second = Int(context.date.timeIntervalSince(start)) % 16
                    Text(second < 4 ? "Breathe in…" : second < 8 ? "Hold…" : second < 12 ? "Breathe out…" : "Rest…").foregroundStyle(.purple)
                }
            }
            if let start = eyeBreakSince {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    HStack { Text("Look about 20 feet away · \(max(0,20-Int(context.date.timeIntervalSince(start)))) seconds"); Button("Done / Skip") { eyeBreakSince = nil; breaks += 1 } }
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
            if !agenda.calendarConnected { Button("Connect Calendar") { Task { await agenda.connect(events:true) } } }
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
            if !agenda.remindersConnected { Button("Connect Reminders") { Task { await agenda.connect(events:false) } } }
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
struct IslandDayView: View {
    @ObservedObject var agenda = IslandAgenda.shared
    var body: some View {
        TimelineView(.periodic(from:.now,by:60)) { context in
            let start = Calendar.current.startOfDay(for:context.date)
            let next = Calendar.current.date(byAdding:.day,value:1,to:start) ?? start.addingTimeInterval(86400)
            let progress = context.date.timeIntervalSince(start)/next.timeIntervalSince(start)
            VStack(alignment:.leading,spacing:10) {
                HStack { Text("Today").font(.headline); Spacer(); Text("\(Int(progress*100))% of the day").foregroundStyle(.secondary) }
                ProgressView(value:progress).tint(.orange)
                ForEach(agenda.events.filter { Calendar.current.isDateInToday($0.startDate) },id:\.calendarItemIdentifier) { event in HStack { Text(event.startDate,style:.time); Text(event.title ?? "Event").foregroundStyle(.secondary) } }
                if !agenda.calendarConnected { Text("Connect Calendar in its module to add your schedule to this timeline.").font(.caption).foregroundStyle(.secondary) }
            }
        }.task { await agenda.refresh() }
    }
}

struct IslandLauncherView: View {
    struct Item: Codable,Identifiable { var id: String; var title: String; var bookmark: Data }
    @State var items: [Item] = []
    @State var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Launcher").font(.headline); Spacer(); Button("Add app or folder…") { add() } }
            HStack { ForEach(items) { item in
                VStack { Button(item.title) { open(item) }.buttonStyle(.bordered); Button("Remove") { items.removeAll { $0.id == item.id }; save() }.font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary) }
            } }
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
