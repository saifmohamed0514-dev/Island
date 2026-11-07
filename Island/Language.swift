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
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { IslandMark(size:40);Text("Island guide").font(.title2);Spacer();Button("Done") { dismiss() } }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    help("Make it yours","In Settings → Modules, drag module cards onto the black preview to add them. Drag icons to arrange them, click a card or icon for settings, and drop onto Drop here to hide to hide a module. How it works explains the gestures; Undo restores the previous layout. The first five appear in the strip; the others are under More. Pin keeps Island open.")
                    help("Focus","Pause before dragging the ring. Add custom presets with +. Focus & Sounds has work/break cycles, ringtone import and silent mode. A completed compact timer clears automatically.")
                    help("ChatGPT, Claude and Cursor","Prepare a private bridge folder in Agents & Inbox. ChatGPT Work and Codex use the included hook example or plugin. Review and trust the hooks in the client. Only one request is approved per click. Regular web chats do not emit local hooks.")
                    help("Power controls","Open Settings → Permissions, select Low Power Mode and choose Set up selected. Approve macOS once. Ordinary toggles then work without repeated passwords. Local unsigned preview updates may need setup again; stable Developer ID signed releases can preserve the trusted signing identity.")
                    help("Windows and alerts","Window Snapping is opt-in and requires Accessibility. Wellbeing & Alerts has goals, intervals and battery thresholds. Permissions contains the guided access checklist. Island’s inbox contains its own alerts and alerts explicitly forwarded to it.")
                    help("Your data","Notes, bookmarks, timers, device reminders and usage counters stay on this Mac. OpenAI translation sends the entered text only after you choose OpenAI and Translate. Tokens are stored in Keychain.")
                    Button("Copy diagnostic summary") {
                        let info="Island "+(Bundle.main.releaseVersionNumber ?? "")+" ("+(Bundle.main.buildVersionNumber ?? "")+")\n"+ProcessInfo.processInfo.operatingSystemVersionString+"\nDisplays: "+String(NSScreen.screens.count)+"\nModules: "+String(IslandModuleStore.shared.enabled.count)
                        NSPasteboard.general.clearContents();NSPasteboard.general.setString(info,forType:.string)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(24).frame(width:620,height:560)
    }
    func help(_ title:String,_ text:String)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.headline);Text(text).foregroundStyle(.secondary) } }
}
