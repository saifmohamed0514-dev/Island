import SwiftUI

struct IslandLanguageSettings:View {
    @AppStorage("island.language") var language="system"
    @State var changed=false
    var body:some View {
        Form {
            Section("App language") {
                Picker("Language",selection:$language) { Text("Follow system").tag("system");Text("English").tag("en");Text("العربية").tag("ar") }
                Text("Restart Island to apply your choice. Your notes, file tray and timer are saved.").foregroundStyle(.secondary)
                if changed { Button("Restart Island") { ApplicationRelauncher.restart() } }
            }
            Section("Translations") { Text("English and Arabic interface labels are included. Some detailed integration messages use English while translation coverage is expanded.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).onChange(of:language) {
            if language == "system" { UserDefaults.standard.removeObject(forKey:"AppleLanguages") } else { UserDefaults.standard.set([language],forKey:"AppleLanguages") };changed=true
        }
    }
}
struct IslandHelpView:View {
    @Environment(\.dismiss) var dismiss
    @State private var copied=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { IslandMark(size:40);Text("Island guide").font(.title2);Spacer();Button("Done") { dismiss() } }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    help("Make it yours","In Settings → Modules, drop module cards into the spaces inside the black preview. Drag blocks between spaces to swap. Click a block for settings. The first drop applies the layout to your real Island; click its blocks for full controls and use the grid button to return. Undo restores the previous arrangement. The first five appear in the strip; the others are under More. Pin keeps Island open.")
                    help("Focus","Pause before dragging the ring. Add custom presets with +. Focus & Sounds has work/break cycles, ringtone import and silent mode. A completed compact timer clears automatically.")
                    help("AI plugins","Get the hook-free plugins in Agents & Inbox. Review and enable the matching plugin in your client, then select Island for a task. It reports progress and can ask questions you answer in the notch. Native security approvals stay in the original app. Older client connections remain optional under Advanced.")
                    help("Power controls","Open Settings → Permissions, select Low Power Mode and choose Set up selected. Approve macOS once. Ordinary toggles then work without repeated passwords. Local unsigned preview updates may need setup again; stable Developer ID signed releases can preserve the trusted signing identity.")
                    help("Windows and alerts","Window Snapping is opt-in and requires Accessibility. Wellbeing & Alerts has goals, intervals and battery thresholds. Permissions contains the guided access checklist. Island’s inbox contains its own alerts and alerts explicitly forwarded to it.")
                    help("Your data","Notes, bookmarks, timers, device reminders and usage counters stay on this Mac. OpenAI translation sends the entered text only after you choose OpenAI and Translate. Tokens are stored in Keychain.")
                    Button(copied ? "Copied diagnostic summary" : "Copy diagnostic summary") {
                        let setup=IslandPermissionSetup.shared
                        let permissions=IslandPermission.visibleCases.map { $0.title+": "+setup.status($0).label }.joined(separator:"\n")
                        let info="Island "+(Bundle.main.releaseVersionNumber ?? "")+" ("+(Bundle.main.buildVersionNumber ?? "")+")\n"+ProcessInfo.processInfo.operatingSystemVersionString+"\nDisplays: "+String(NSScreen.screens.count)+"\nModules enabled: "+String(IslandModuleStore.shared.enabled.count)+"\nCustom layout: "+String(IslandCanvasStore.shared.preferences.enabled)+"\nMedia key handler: "+String(MediaKeyInterceptor.shared.isRunning)+"\nUpdate channel: "+(IslandUpdateConfiguration.isConfigured ? "connected" : "not connected")+"\nPermission status (last checked):\n"+permissions
                        NSPasteboard.general.clearContents();NSPasteboard.general.setString(info,forType:.string);copied=true
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(24).frame(width:620,height:560)
    }
    func help(_ title:String,_ text:String)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.headline);Text(text).foregroundStyle(.secondary) } }
}
