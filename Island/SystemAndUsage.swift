import SwiftUI
import Combine
import Darwin
import CoreGraphics
import Charts

struct IslandSystemSample {
    var cpu: Double?
    var usedMemory: Double = 0
    var totalMemory: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var freeDisk: Double?
    var totalDisk: Double?
    var previous: [UInt32]?
    mutating func update() {
        var cpu = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpu) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if result == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0,cpu.cpu_ticks.1,cpu.cpu_ticks.2,cpu.cpu_ticks.3]
            if let last = previous {
                let delta = zip(ticks,last).map { Double($0 &- $1) }; let total = delta.reduce(0,+)
                if total > 0 { self.cpu = min(1,max(0,1 - delta[2]/total)) }
            }
            previous = ticks
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to:&vm) { ptr in ptr.withMemoryRebound(to:integer_t.self, capacity:Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if status == KERN_SUCCESS { usedMemory = min(totalMemory, Double(vm.active_count + vm.wire_count) * Double(vm_kernel_page_size) + Double(vm.compressor_page_count) * Double(vm_kernel_page_size)) }
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey,.volumeAvailableCapacityForImportantUsageKey]) {
            totalDisk = values.volumeTotalCapacity.map(Double.init); freeDisk = values.volumeAvailableCapacityForImportantUsage.map(Double.init)
        }
    }
}
struct IslandSystemView: View {
    @State var sample = IslandSystemSample()
    var body: some View {
        VStack(spacing: 12) {
            IslandModuleHeading(title:"System Monitor", subtitle:"Live · updated each second")
            HStack(spacing: 20) {
                metric("CPU", value: sample.cpu.map { String(format:"%.0f%%",$0*100) } ?? "—", progress: sample.cpu ?? 0)
                metric("Memory", value: "\(String(format:"%.1f",sample.usedMemory / 1073741824)) / \(Int(sample.totalMemory / 1073741824)) GiB", progress: sample.usedMemory / sample.totalMemory)
                metric("Storage", value: sample.freeDisk.map { "\(Int($0/1e9)) GB free" } ?? "Unavailable", progress: (sample.freeDisk != nil && sample.totalDisk != nil) ? 1 - sample.freeDisk! / sample.totalDisk! : 0)
            }
        }.task { while !Task.isCancelled { sample.update(); try? await Task.sleep(for:.seconds(1)) } }
    }
    func metric(_ title: String, value: String, progress: Double) -> some View {
        VStack(alignment:.leading,spacing:8) { Text(title).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit(); ProgressView(value:min(1,max(0,progress))).tint(.cyan) }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
@MainActor final class IslandUsageTracker: ObservableObject {
    static let shared = IslandUsageTracker()
    struct Entry: Codable { var name: String; var seconds: Double; var switches: Int }
    @Published var entries: [String: Entry] = [:]
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var last = Date()
    private var day: String = ""
    private var activeApp:(id:String,name:String)?
    @Published var undoEntries:[String:Entry]?
    func setEnabled(_ enabled: Bool) {
        guard enabled else { timer?.invalidate(); timer = nil; if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer); self.observer = nil }; return }
        guard timer == nil else { return }; loadDay()
        last = Date();if let app=NSWorkspace.shared.frontmostApplication,let id=app.bundleIdentifier { activeApp=(id,app.localizedName ?? id) }
        timer = Timer.scheduledTimer(withTimeInterval: 10,repeats:true) { [weak self] _ in Task { @MainActor in self?.record() } }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] notice in
            guard let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let id = app.bundleIdentifier else { return }
            Task { @MainActor in
                guard let self else { return }; self.record();self.activeApp=(id,app.localizedName ?? id);self.loadDay();guard !self.excluded.contains(id) else { return }; var entry = self.entries[id] ?? Entry(name:app.localizedName ?? id,seconds:0,switches:0); entry.switches += 1; self.entries[id] = entry; self.persist()
            }
        }
    }
    private var resetHour:Int { min(23,max(0,UserDefaults.standard.integer(forKey:"island.usage.resetHour"))) }
    private func dayStart(_ date:Date)->Date {
        let shifted=Calendar.current.date(byAdding:.hour,value:-resetHour,to:date) ?? date
        return Calendar.current.date(byAdding:.hour,value:resetHour,to:Calendar.current.startOfDay(for:shifted)) ?? Calendar.current.startOfDay(for:date)
    }
    private var excluded:Set<String> { Set((UserDefaults.standard.string(forKey:"island.usage.excluded") ?? "").split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }) }
    private func loadDay() {
        let today = String(Int(dayStart(Date()).timeIntervalSince1970))
        if day != today { undoEntries=nil;day = today; entries = (UserDefaults.standard.data(forKey:"island.usage."+day).flatMap { try? JSONDecoder().decode([String:Entry].self,from:$0) }) ?? [:] }
    }
    private func record() {
        loadDay(); let now = Date(); defer { last = now }
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!) < 120,
              let activeApp,now.timeIntervalSince(last) >= 0,now.timeIntervalSince(last) <= 20 else { return }
        let id=activeApp.id
        guard !excluded.contains(id) else { return }
        var entry = entries[id] ?? Entry(name:activeApp.name,seconds:0,switches:0)
        entry.seconds += max(0,now.timeIntervalSince(max(last,dayStart(now)))); entries[id] = entry; persist()
    }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(entries),forKey:"island.usage."+day) }
    func clearToday() { undoEntries=entries;entries=[:];persist() }
    func undoClear() {
        guard let backup=undoEntries else { return };for (id,value) in backup { var entry=entries[id] ?? Entry(name:value.name,seconds:0,switches:0);entry.seconds += value.seconds;entry.switches += value.switches;entries[id]=entry };undoEntries=nil;persist()
    }
    func history(daysAgo:Int)->[String:Entry] {
        guard daysAgo != 0 else { return entries }
        let date=Calendar.current.date(byAdding:.day,value:-daysAgo,to:Date()) ?? Date(),key=String(Int(dayStart(date).timeIntervalSince1970))
        return UserDefaults.standard.data(forKey:"island.usage."+key).flatMap { try? JSONDecoder().decode([String:Entry].self,from:$0) } ?? [:]
    }
}
struct IslandUsageView:View {
    @ObservedObject var usage=IslandUsageTracker.shared
    @State var daysAgo=0
    @AppStorage("island.usage.categories") var categoryData=Data()
    let categories=["Work","Communication","Entertainment","Other"]
    var labels:[String:String] { (try? JSONDecoder().decode([String:String].self,from:categoryData)) ?? [:] }
    var selected:[String:IslandUsageTracker.Entry] { usage.history(daysAgo:daysAgo) }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Screen Time").font(.headline);Spacer();Picker("Day",selection:$daysAgo) { Text("Today").tag(0);ForEach(1...6,id:\.self) { value in Text("\(value) days ago").tag(value) } }.frame(width:165) }
            Chart(Array((0...6).reversed()),id:\.self) { offset in
                let date=Calendar.current.date(byAdding:.day,value:-offset,to:Date()) ?? Date(),seconds=usage.history(daysAgo:offset).values.reduce(0) { $0+$1.seconds }
                BarMark(x:.value("Day",date,unit:.day),y:.value("Minutes",seconds/60)).foregroundStyle(.cyan.gradient)
            }.frame(height:70)
            if selected.isEmpty { Text("No tracked activity for this day. Tracking runs only while this module is enabled.").font(.caption).foregroundStyle(.secondary) }
            HStack { ForEach(categories,id:\.self) { category in
                let seconds=selected.filter { labels[$0.key,default:"Other"] == category }.values.reduce(0) { $0+$1.seconds }
                Text("\(category): \(Int(seconds/60))m").font(.caption2).foregroundStyle(.secondary)
            } }
            ForEach(selected.sorted { $0.value.seconds > $1.value.seconds },id:\.key) { pair in
                HStack { Text(pair.value.name);Spacer();Picker("Category",selection:Binding(get:{ labels[pair.key,default:"Other"] },set:{ value in var map=labels;map[pair.key]=value;categoryData=(try? JSONEncoder().encode(map)) ?? Data() })) { ForEach(categories,id:\.self) { Text($0).tag($0) } }.labelsHidden().frame(width:130);Text("\(Int(pair.value.seconds/60))m · \(pair.value.switches) switches").font(.caption).foregroundStyle(.secondary) }
            }
            HStack { Button("Clear today’s counters",role:.destructive) { usage.clearToday() }.font(.caption);if usage.undoEntries != nil { Button("Undo clear") { usage.undoClear() }.font(.caption) };Spacer();Text("Local counters · idle time excluded").font(.caption2).foregroundStyle(.secondary) }
        }.onAppear { usage.setEnabled(true) }
    }
}

struct IslandUsageSettings:View {
    @AppStorage("island.usage.resetHour") private var resetHour=0
    @AppStorage("island.usage.excluded") private var excluded=""
    @ObservedObject private var modules=IslandModuleStore.shared
    var body:some View { Form {
        Section("Local app counters") { Toggle("Record app usage",isOn:Binding(get:{ modules.enabled.contains(.usage) },set:{ modules.setEnabled(.usage,$0) }));Text("App names, active minutes and switch counts stay on this Mac. Idle time is excluded.").font(.caption).foregroundStyle(.secondary) }
        Section("Your day") { Picker("Start a new day at",selection:$resetHour) { ForEach(0..<24,id:\.self) { Text(String(format:"%02d:00",$0)).tag($0) } };Text("Changing the day boundary selects a separate daily bucket. Existing history is kept.").font(.caption).foregroundStyle(.secondary) }
        Section("Excluded apps") { TextField("Bundle IDs, separated by commas",text:$excluded);Text("For example: com.apple.finder, com.apple.Terminal. These apps won’t add time or switch counts while excluded.").font(.caption).foregroundStyle(.secondary) }
    }.formStyle(.grouped) }
}
