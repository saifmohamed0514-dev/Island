import SwiftUI
import Defaults
import LaunchAtLogin
import Sparkle
import KeyboardShortcuts

struct IslandSettingsView:View {
    @State var selected = "Overview"
    let updaterController:SPUStandardUpdaterController?
    let pages:[(String,String)] = [("Overview","capsule"),("Modules","square.grid.2x2"),("Dashboard","rectangle.grid.2x2"),("Focus & Sounds","timer"),("Displays","display.2"),("Window Snapping","macwindow"),("Media","music.note"),("Behavior","cursorarrow.rays"),("System Controls","switch.2"),("Wellbeing & Alerts","heart"),("Connections","network"),("Agents & Inbox","terminal"),("Language","globe"),("About Island","info.circle")]
    var body:some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:18) {
                HStack(spacing:10) { IslandMark(size:36); VStack(alignment:.leading,spacing:2) { Text("Island").font(.system(size:18,weight:.semibold,design:.rounded)); Text("Make space.").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal,16).padding(.top,20)
                List(selection:$selected) { ForEach(pages,id:\.0) { page in Label(LocalizedStringKey(page.0),systemImage:page.1).tag(page.0).padding(.vertical,3) } }.listStyle(.sidebar)
            }.navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selected {
                case "Modules": IslandModulesSettings()
                case "Dashboard": IslandDashboardSettings()
                case "Focus & Sounds": IslandFocusSettings()
                case "Displays": IslandDisplaySettings()
                case "Window Snapping": IslandWindowSettings()
                case "Media": IslandMediaSettings()
                case "Behavior": IslandBehaviorSettings()
                case "System Controls": IslandSystemSettings()
                case "Wellbeing & Alerts": IslandWellbeingSettings()
                case "Connections": IslandConnectionsSettings()
                case "Agents & Inbox": IslandBridgeSettings()
                case "Language": IslandLanguageSettings()
                case "About Island": IslandAboutSettings(updater:updaterController)
                default: IslandOverviewSettings { selected = $0 }
                }
            }.navigationTitle(LocalizedStringKey(selected)).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:760,height:610).navigationSplitViewStyle(.balanced).tint(.blue)
    }
}
struct IslandOverviewSettings:View {
    var navigate:(String)->Void
    @ObservedObject var modules = IslandModuleStore.shared
    var body:some View {
        Form {
            Section {
                HStack(spacing:18) { IslandMark(size:64); VStack(alignment:.leading,spacing:6) { Text("A little space. A lot within reach.").font(.title2.weight(.semibold)); Text("Music, focus, files and the tools you choose. Quiet until you need them.").foregroundStyle(.secondary) } }.padding(.vertical,12)
            }
            Section("Your Island") {
                LabeledContent("Enabled modules",value:"\(modules.enabled.count)")
                LabeledContent("Opens with",value:modules.defaultModule.title)
                HStack { Button("Choose modules") { navigate("Modules") }; Button("Set up focus") { navigate("Focus & Sounds") } }
            }
            Section("Start small") { Text("Enable only what you use. Optional data connections and permissions are requested when you choose them, and your notes and timer stay on this Mac.").foregroundStyle(.secondary) }
            Section("Release channel") { Label(IslandUpdateConfiguration.isConfigured ? "Signed update channel connected" : "Local preview · update channel not connected",systemImage:"arrow.down.circle").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}
struct IslandDisplaySettings:View {
    @ObservedObject var coordinator = IslandCoordinator.shared
    @Default(.showOnAllDisplays) var allDisplays
    @Default(.automaticallySwitchDisplay) var followPointer
    @Default(.nonNotchHeightMode) var heightMode
    @Default(.nonNotchHeight) var height
    @State var screens:[NSScreen] = NSScreen.screens
    var body:some View {
        Form {
            Section("Where Island lives") {
                Toggle("Show on every display",isOn:$allDisplays).onChange(of:allDisplays) { NotificationCenter.default.post(name:.showOnAllDisplaysChanged,object:nil) }
                Picker("Preferred display",selection:$coordinator.preferredScreenUUID) { ForEach(screens,id:\.displayUUID) { screen in Text(screen.localizedName).tag(screen.displayUUID) } }.disabled(allDisplays)
                Toggle("Follow the active display",isOn:$followPointer).disabled(allDisplays).onChange(of:followPointer) { NotificationCenter.default.post(name:.automaticallySwitchDisplayChanged,object:nil) }
            }
            Section("Displays without a camera notch") {
                Picker("Collapsed height",selection:$heightMode) { Text("Match menu bar").tag(WindowHeightMode.matchMenuBar); Text("Custom").tag(WindowHeightMode.custom) }
                if heightMode == .custom { Slider(value:$height,in:22...44,step:1) { Text("Height") }; Text("\(Int(height)) points").foregroundStyle(.secondary) }
                Text("Island stays centered at the top edge. On displays with a camera notch, activity sits beside the camera, not underneath it.").foregroundStyle(.secondary)
            }.onChange(of:heightMode) { NotificationCenter.default.post(name:.notchHeightChanged,object:nil) }.onChange(of:height) { NotificationCenter.default.post(name:.notchHeightChanged,object:nil) }
        }.formStyle(.grouped).onReceive(NotificationCenter.default.publisher(for:NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }
}
struct IslandMediaSettings:View {
    @Default(.mediaController) var source
    @ObservedObject var coordinator = IslandCoordinator.shared
    var body:some View {
        Form {
            Section("Your player") {
                Picker("Music source",selection:$source) { ForEach(MediaControllerType.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Show music beside the notch",isOn:$coordinator.musicLiveActivityEnabled)
                Text("Now Playing works with supported apps and browsers. Playback and seeking depend on the chosen player.").foregroundStyle(.secondary)
            }
            Section("Artwork") { Text("Island uses the player's real artwork and metadata. When music is idle, it shows Not Playing once.").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}
struct IslandBehaviorSettings:View {
    @Default(.menubarIcon) var menuIcon
    @Default(.openNotchOnHover) var hover
    @Default(.minimumHoverDuration) var delay
    @Default(.enableHaptics) var haptics
    @Default(.hideFromScreenRecording) var privacy
    @Default(.hideNotchOption) var hideInFullscreen
    @ObservedObject var coordinator = IslandCoordinator.shared
    var body:some View {
        Form {
            Section("Everyday") {
                LaunchAtLogin.Toggle("Open Island at login")
                Toggle("Show menu bar icon",isOn:$menuIcon)
                Toggle("Open when the pointer rests on Island",isOn:$hover)
                Slider(value:$delay,in:0.05...1,step:0.05) { Text("Hover delay") }; Text(String(format:"%.2f seconds",delay)).foregroundStyle(.secondary)
                Toggle("Haptic feedback",isOn:$haptics)
                Toggle("Remember the last module",isOn:$coordinator.openLastTabByDefault)
                Picker("Hide in full screen",selection:$hideInFullscreen) { Text("Never").tag(HideNotchOption.never); Text("Media apps").tag(HideNotchOption.nowPlayingOnly); Text("Always").tag(HideNotchOption.always) }
            }
            Section("Keyboard shortcuts") {
                KeyboardShortcuts.Recorder("Open Island",name:.toggleNotchOpen)
                KeyboardShortcuts.Recorder("Quick peek",name:.toggleSneakPeek)
                KeyboardShortcuts.Recorder("Microphone",name:.toggleMicrophone)
            }
            Section("Privacy") {
                Toggle("Ask macOS to hide Island from captures",isOn:$privacy)
                Text("Capture exclusion depends on the recording app and macOS version. Screen Time is optional and stores app-use counters locally.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
struct IslandSystemSettings:View {
    @Default(.hudReplacement) var hud
    @Default(.showBatteryIndicator) var battery
    var body:some View {
        Form {
            Section("System overlays") {
                Toggle("Replace volume and brightness HUDs",isOn:$hud)
                Button("Review Accessibility access…") { Task { _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded:true) } }
                Text("Accessibility permission enables HUD replacement and the window-layout module. Island never grants it automatically.").foregroundStyle(.secondary)
            }
            Section("Battery") { IslandPowerSwitch();Toggle("Show battery in Island",isOn:$battery); Text("The battery pop-up follows system appearance and uses native glass where macOS supports it.").foregroundStyle(.secondary) }
            Section("Personal data") {
                Button("Connect Calendar") { Task { await IslandAgenda.shared.connect(events:true) } }
                Button("Connect Reminders") { Task { await IslandAgenda.shared.connect(events:false) } }
                Text("Camera access is requested only when you start the Mirror module. You can revoke permissions in System Settings.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
struct IslandAboutSettings:View {
    let updater:SPUStandardUpdaterController?
    @State var help=false
    var body:some View {
        Form {
            Section {
                HStack(spacing:16) { IslandMark(size:58); VStack(alignment:.leading,spacing:5) { Text("Island").font(.largeTitle.weight(.semibold)); Text("Version \(Bundle.main.releaseVersionNumber ?? "") · Build \(Bundle.main.buildVersionNumber ?? "")").foregroundStyle(.secondary) } }.padding(.vertical,12)
                Text("An independent, open-source workspace for the top of your Mac.")
            }
            Section("Help") { Button("Island guide") { help=true } }
            Section("Updates") {
                if let updater, IslandUpdateConfiguration.isConfigured { CheckForUpdatesView(updater:updater.updater) }
                else { Text("Updates are not connected for this local preview.").foregroundStyle(.secondary) }
            }
            Section("Open-source credits") {
                Text("Island includes GPL-3.0 code from Boring Notch and other open-source components. Their copyright and license notices remain included. The Island interface is independently designed.").font(.caption).foregroundStyle(.secondary)
                Link("Original project and license",destination:URL(string:"https://github.com/TheBoredTeam/boring.notch")!)
            }
        }.formStyle(.grouped).sheet(isPresented:$help) { IslandHelpView() }
    }
}
struct IslandMirrorView:View {
    @ObservedObject var camera = WebcamManager.shared
    @EnvironmentObject var vm:IslandViewModel
    var body:some View {
        VStack(spacing:8) {
            if camera.isSessionRunning { CameraPreviewView(webcamManager:camera).scaledToFill().frame(height:105).clipped().clipShape(RoundedRectangle(cornerRadius:18)); Button("Turn camera off") { camera.stopSession() } }
            else { Image(systemName:"video.slash").font(.title).foregroundStyle(.secondary); Text("A quick check, on your terms.").foregroundStyle(.secondary); Button("Start mirror") { vm.toggleCameraPreview() } }
        }.frame(maxWidth:.infinity).onDisappear { camera.stopSession() }
    }
}
