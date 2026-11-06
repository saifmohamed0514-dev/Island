import SwiftUI
import Combine
import Darwin
import CoreGraphics

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
    func setEnabled(_ enabled: Bool) {
        guard enabled else { timer?.invalidate(); timer = nil; if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer); self.observer = nil }; return }
        guard timer == nil else { return }; loadDay()
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 10,repeats:true) { [weak self] _ in Task { @MainActor in self?.record() } }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] notice in
            guard let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let id = app.bundleIdentifier else { return }
            Task { @MainActor in
                guard let self else { return }; self.loadDay(); var entry = self.entries[id] ?? Entry(name:app.localizedName ?? id,seconds:0,switches:0); entry.switches += 1; self.entries[id] = entry; self.persist()
            }
        }
    }
    private func loadDay() {
        let today = String(Int(Calendar.current.startOfDay(for:Date()).timeIntervalSince1970))
        if day != today { day = today; entries = (UserDefaults.standard.data(forKey:"island.usage."+day).flatMap { try? JSONDecoder().decode([String:Entry].self,from:$0) }) ?? [:] }
    }
    private func record() {
        loadDay(); let now = Date(); defer { last = now }
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!) < 120,
              let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return }
        var entry = entries[id] ?? Entry(name:app.localizedName ?? id,seconds:0,switches:0)
        entry.seconds += max(0,min(15,now.timeIntervalSince(last))); entries[id] = entry; persist()
    }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(entries),forKey:"island.usage."+day) }
    func clearToday() { entries = [:]; persist() }
}
struct IslandUsageView: View {
    @ObservedObject var usage = IslandUsageTracker.shared
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            IslandModuleHeading(title:"Screen Time",subtitle:"Today · active use only · stored locally")
            if usage.entries.isEmpty { Text("Tracking starts when this module is enabled. Idle time over two minutes is excluded.").foregroundStyle(.secondary) }
            ForEach(usage.entries.sorted { $0.value.seconds > $1.value.seconds },id:\.key) { pair in
                HStack { Text(pair.value.name); Spacer(); Text("\(Int(pair.value.seconds/60))m · \(pair.value.switches) switches").foregroundStyle(.secondary) }
            }
            Button("Clear today’s counters",role:.destructive) { usage.clearToday() }.font(.caption)
        }.onAppear { usage.setEnabled(true) }
    }
}
