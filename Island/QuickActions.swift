import SwiftUI
import AppKit
import IOKit.pwr_mgt

@MainActor final class IslandQuickActions:ObservableObject {
    static let shared=IslandQuickActions()
    @Published private(set) var keepingAwake=false
    @Published private(set) var error=""
    private var assertion=IOPMAssertionID(0)
    func setAwake(_ value:Bool) {
        if assertion != 0 { IOPMAssertionRelease(assertion);assertion=0 }
        keepingAwake=false;error=""
        if value {
            let result=IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,IOPMAssertionLevel(kIOPMAssertionLevelOn),"Island keeps this Mac awake at your request" as CFString,&assertion)
            keepingAwake=result == kIOReturnSuccess
            if !keepingAwake { error="This Mac couldn’t enable Keep Awake." }
        }
    }
}
struct IslandQuickActionsView:View {
    @ObservedObject private var model=IslandQuickActions.shared
    @AppStorage("island.awake.restore") private var restore=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Quick actions").font(.caption).foregroundStyle(.secondary);Spacer();Toggle("Keep this Mac awake",isOn:Binding(get:{ model.keepingAwake },set:{ model.setAwake($0);IslandHaptics.play(.confirmation) })).toggleStyle(.switch) }
            Toggle("Restore Keep Awake when Island launches",isOn:$restore).font(.caption)
            Text("Prevents idle system sleep while Island is running. Closing the lid, locking, or choosing Sleep still belongs to macOS.").font(.caption2).foregroundStyle(.secondary)
            HStack { Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Shortcuts.app")) };Button("Power controls…") { IslandSettingsController.shared.showPermissions(.power) } }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
