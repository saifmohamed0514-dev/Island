import SwiftUI
import Combine

@MainActor final class IslandWellbeingReminders {
    static let shared=IslandWellbeingReminders()
    private var task:Task<Void,Never>?
    private var waterDue=Date(),breakDue=Date()
    func configure(_ enabled:Bool) {
        task?.cancel();task=nil;guard enabled,UserDefaults.standard.bool(forKey:"island.health.reminders") else { return }
        let defaults=UserDefaults.standard
        waterDue=Date().addingTimeInterval(Double(max(15,defaults.object(forKey:"island.health.waterInterval") as? Int ?? 60))*60)
        breakDue=Date().addingTimeInterval(Double(max(15,defaults.object(forKey:"island.health.breakInterval") as? Int ?? 45))*60)
        task=Task { [weak self] in while !Task.isCancelled { self?.check();try? await Task.sleep(for:.seconds(30)) } }
    }
    private func check() {
        let now=Date(),defaults=UserDefaults.standard,parts=Calendar.current.dateComponents([.hour,.minute],from:now),minute=(parts.hour ?? 0)*60+(parts.minute ?? 0)
        let windDown=defaults.object(forKey:"island.health.windDown") as? Int ?? 1260
        if minute >= 480 && minute < windDown {
            if now >= waterDue { IslandNotices.shared.post(title:"A moment to recharge",body:"Take a water break when you’re ready.",source:"Wellbeing");waterDue=now.addingTimeInterval(Double(max(15,defaults.object(forKey:"island.health.waterInterval") as? Int ?? 60))*60) }
            if now >= breakDue { IslandNotices.shared.post(title:"Make room for a pause",body:"Rest your eyes, move a little, or check your headphone volume.",source:"Wellbeing");breakDue=now.addingTimeInterval(Double(max(15,defaults.object(forKey:"island.health.breakInterval") as? Int ?? 45))*60) }
        }
        let stamp=String(Int(Calendar.current.startOfDay(for:now).timeIntervalSince1970))
        if minute >= windDown && defaults.string(forKey:"island.health.lastWindDown") != stamp { defaults.set(stamp,forKey:"island.health.lastWindDown");IslandNotices.shared.post(title:"Ease into your evening",body:"A little space away from your screen. Your work will be here when you return.",source:"Wellbeing") }
    }
}
struct IslandWellbeingSettings:View {
    @AppStorage("island.health.waterGoal") var water=8
    @AppStorage("island.health.breakGoal") var breaks=6
    @AppStorage("island.health.mindfulGoal") var mindful=5
    @AppStorage("island.health.reminders") var reminders=false
    @AppStorage("island.health.waterInterval") var waterInterval=60
    @AppStorage("island.health.breakInterval") var breakInterval=45
    @AppStorage("island.health.windDown") var windDown=1260
    @AppStorage("island.devices.alerts") var deviceAlerts=false
    @AppStorage("island.devices.threshold") var threshold=20
    @State var status=""
    var body:some View {
        Form {
            Section("Daily goals") { Stepper("Water: \(water) glasses",value:$water,in:1...30);Stepper("Movement: \(breaks) breaks",value:$breaks,in:1...24);Stepper("Mindfulness: \(mindful) sessions",value:$mindful,in:1...20) }
            Section("Gentle reminders") {
                Toggle("Water, movement and wind-down reminders",isOn:$reminders)
                Stepper("Water every \(waterInterval) minutes",value:$waterInterval,in:15...240,step:15)
                Stepper("Movement every \(breakInterval) minutes",value:$breakInterval,in:15...180,step:15)
                Picker("Wind down",selection:$windDown) { ForEach(17...23,id:\.self) { hour in Text("\(hour):00").tag(hour*60) } }
                Text("Runs while Island and the Wellbeing module are enabled. Water and movement reminders pause overnight, from wind-down until 08:00.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Device batteries") {
                Toggle("Notify when a device battery is low",isOn:$deviceAlerts)
                Stepper("Notify at \(threshold)%",value:$threshold,in:5...50,step:5)
                Text("Requires the Bluetooth module. Alerts use battery levels reported by macOS; not every accessory exposes them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Alerts") { Button("Set up notifications…") { IslandSettingsController.shared.showPermissions(.notifications) };Text("Island also keeps these alerts in its own Inbox. This does not read notifications from unrelated apps.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).onChange(of:reminders) { configure() }.onChange(of:waterInterval) { configure() }.onChange(of:breakInterval) { configure() }.onChange(of:windDown) { configure() }.onChange(of:deviceAlerts) { IslandDevices.shared.configure(IslandModuleStore.shared.enabled.contains(.devices)) }
    }
    func configure() { IslandWellbeingReminders.shared.configure(IslandModuleStore.shared.enabled.contains(.health)) }
}
