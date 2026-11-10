import SwiftUI
import Defaults
import LaunchAtLogin
import Sparkle
import KeyboardShortcuts

@MainActor final class IslandSettingsNavigation:ObservableObject {
    static let shared=IslandSettingsNavigation()
    @Published var selected="Overview"
    @Published var requestedPermission:IslandPermission?
}
struct IslandSettingsPage:Identifiable {
    let route:String;let icon:String;let keywords:String
    var id:String { route }
}
struct IslandSettingsGroup:Identifiable {
    let title:String;let pages:[IslandSettingsPage]
    var id:String { title }
}
enum IslandSettingsCatalog {
    static let groups:[IslandSettingsGroup]=[
        .init(title:"Get started",pages:[.init(route:"Overview",icon:"capsule",keywords:"welcome setup help start"),.init(route:"Permissions",icon:"checkmark.shield",keywords:"privacy access allow approval camera bluetooth calendar reminders touch id"),.init(route:"Help & Tips",icon:"questionmark.circle",keywords:"guide instructions tutorial what how glossary help")]),
        .init(title:"Make it yours",pages:[.init(route:"Modules",icon:"square.grid.2x2",keywords:"layout notch preview drag arrange sections"),.init(route:"Dashboard",icon:"rectangle.grid.2x2",keywords:"widgets profiles schedule focus"),.init(route:"Live Activities",icon:"waveform",keywords:"compact collapsed rotate calendar bluetooth timer source"),.init(route:"Displays",icon:"display.2",keywords:"screen external monitor location"),.init(route:"Behavior",icon:"cursorarrow.rays",keywords:"login startup shortcuts haptics hover snooze")]),
        .init(title:"Daily tools",pages:[.init(route:"Focus & Sounds",icon:"timer",keywords:"timer pomodoro ringtone preset"),.init(route:"Media",icon:"music.note",keywords:"music spotify apple player artwork"),.init(route:"Window Snapping",icon:"macwindow",keywords:"windows tile resize halves corners"),.init(route:"Wellbeing & Alerts",icon:"heart",keywords:"health water breaks breathing notifications")]),
        .init(title:"Connected tools",pages:[.init(route:"System Controls",icon:"switch.2",keywords:"battery power hud volume brightness"),.init(route:"Connections",icon:"network",keywords:"api token key account github jira openai ollama"),.init(route:"Agents & Inbox",icon:"terminal",keywords:"chatgpt codex claude cursor hooks coding messages")]),
        .init(title:"Island",pages:[.init(route:"Updates",icon:"arrow.down.circle",keywords:"automatic update version release install schedule"),.init(route:"Language",icon:"globe",keywords:"arabic english translation"),.init(route:"About Island",icon:"info.circle",keywords:"help guide license credits version")])
    ]
    static func matches(_ page:IslandSettingsPage,query:String)->Bool { query.split(whereSeparator:{ $0.isWhitespace }).allSatisfy { (page.route+" "+page.keywords).localizedCaseInsensitiveContains(String($0)) } }
}
struct IslandSettingsView:View {
    @ObservedObject private var navigation=IslandSettingsNavigation.shared
    @State private var query=""
    @AppStorage("island.settings.helpTipDismissed") private var helpTipDismissed=false
    @FocusState private var searchFocused:Bool
    let updaterController:SPUStandardUpdaterController?
    private var moduleMatches:[NotchViews] { query.isEmpty ? [] : NotchViews.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) || IslandGuideCatalog.module($0).matches(query) } }
    var body:some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:10) { IslandMark(size:36);VStack(alignment:.leading,spacing:2) { Text("Island").font(.system(size:18,weight:.semibold,design:.rounded));Text("Make space.").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal,16).padding(.top,20)
                TextField("Search settings",text:$query).textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityLabel("Search Island settings and modules").padding(.horizontal,12)
                List(selection:$navigation.selected) {
                    ForEach(IslandSettingsCatalog.groups) { group in
                        let pages=group.pages.filter { IslandSettingsCatalog.matches($0,query:query) || IslandGuideCatalog.page($0.route).matches(query) }
                        if !pages.isEmpty { Section(group.title) { ForEach(pages) { page in Label(LocalizedStringKey(page.route),systemImage:page.icon).tag(page.route).padding(.vertical,3) } } }
                    }
                    if !moduleMatches.isEmpty { Section("Module settings") { ForEach(moduleMatches) { module in Button { IslandSettingsController.shared.showModuleDesigner(module) } label: { Label(module.title,systemImage:module.icon).frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain).padding(.vertical,4).accessibilityHint("Open settings for this module") } } }
                    if !query.isEmpty,moduleMatches.isEmpty,!IslandSettingsCatalog.groups.flatMap(\.pages).contains(where:{ IslandSettingsCatalog.matches($0,query:query) || IslandGuideCatalog.page($0.route).matches(query) }) { Text("No matching settings").foregroundStyle(.secondary);Button("Clear search") { query="" } }
                }.listStyle(.sidebar).accessibilityLabel("Settings sections")
            }.navigationSplitViewColumnWidth(min:220,ideal:230,max:280)
        } detail: {
            Group {
                switch navigation.selected {
                case "Permissions":IslandPermissionsView()
                case "Help & Tips":IslandGuidanceSettings()
                case "Modules":IslandModulesSettings()
                case "Dashboard":IslandDashboardSettings()
                case "Live Activities":IslandLiveActivitySettings()
                case "Focus & Sounds":IslandFocusSettings()
                case "Displays":IslandDisplaySettings()
                case "Window Snapping":IslandWindowSettings()
                case "Media":IslandMediaSettings()
                case "Behavior":IslandBehaviorSettings()
                case "System Controls":IslandSystemSettings()
                case "Wellbeing & Alerts":IslandWellbeingSettings()
                case "Connections":IslandConnectionsSettings()
                case "Agents & Inbox":IslandBridgeSettings()
                case "Updates":IslandUpdatesSettings()
                case "Language":IslandLanguageSettings()
                case "About Island":IslandAboutSettings(updater:updaterController)
                default:IslandOverviewSettings { navigation.selected=$0 }
                }
            }.navigationTitle(LocalizedStringKey(navigation.selected)).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:800,minHeight:650).navigationSplitViewStyle(.balanced).tint(.blue)
        .toolbar { ToolbarItem { IslandPageHelp(route:navigation.selected) } }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if !helpTipDismissed {
                HStack(spacing:10) {
                    Image(systemName:"questionmark.circle").foregroundStyle(.blue)
                    Text("Need a hand? The question mark explains the page you’re on.").font(.callout)
                    Spacer()
                    Button("Show help") { navigation.selected="Help & Tips";helpTipDismissed=true }
                    Button { helpTipDismissed=true } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss the Settings help tip")
                }.padding(12).background(.bar)
            }
        }
        .onChange(of:navigation.selected) { IslandHaptics.play(.selection) }
        .background { Button("Find settings") { searchFocused=true }.keyboardShortcut("f",modifiers:.command).hidden() }
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
                HStack { Button("Set up permissions") { navigate("Permissions") };Button("Choose modules") { navigate("Modules") }; Button("Set up focus") { navigate("Focus & Sounds") } }
            }
            Section("Guided setup") { Button("Set up Island…") { NotificationCenter.default.post(name:.islandShowSetup,object:nil) };Text("Review preferences, customize your modules and set up access one step at a time.").foregroundStyle(.secondary) }
            Section("Quick access") { HStack { Button("File Tray") { IslandSettingsController.shared.showModuleDesigner(.shelf) };Button("Window Snapping") { navigate("Window Snapping") };Button("Updates") { navigate("Updates") };Button("Help & Tips") { navigate("Help & Tips") } } }
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
                Button("Manage player permissions…") { IslandSettingsController.shared.showPermissions(source == .spotify ? .spotify : .music) }
                Text("Now Playing works with supported apps and browsers. Playback and seeking depend on the chosen player.").foregroundStyle(.secondary)
            }
            Section("Artwork") { Text("Island uses the player's real artwork and metadata. When music is idle, it shows Not Playing once.").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}
struct IslandBehaviorSettings:View {
    @AppStorage("island.snooze.minutes") private var snoozeMinutes=15
    @AppStorage("island.shortcuts.openOnly") private var openOnly=false
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
                Slider(value:$delay,in:0.05...1,step:0.05) { Text("Hover delay") }.disabled(!hover).help("How long the pointer rests on Island before it opens."); Text(String(format:"%.2f seconds",delay)).foregroundStyle(.secondary)
                Toggle("Haptic feedback",isOn:$haptics).help("Gentle trackpad taps for actions such as placing a module or adjusting the timer, on supported hardware.")
                Toggle("Remember the last module",isOn:$coordinator.openLastTabByDefault)
                Picker("Hide in full screen",selection:$hideInFullscreen) { Text("Never").tag(HideNotchOption.never); Text("Media apps").tag(HideNotchOption.nowPlayingOnly); Text("Always").tag(HideNotchOption.always) }
            }
            Section("Keyboard shortcuts") {
                KeyboardShortcuts.Recorder("Open Island",name:.toggleNotchOpen)
                KeyboardShortcuts.Recorder("Quick peek",name:.toggleSneakPeek)
                KeyboardShortcuts.Recorder("Next module",name:.islandNextModule)
                KeyboardShortcuts.Recorder("Previous module",name:.islandPreviousModule)
                KeyboardShortcuts.Recorder("Snooze or resume Island",name:.islandSnooze)
                Toggle("Change modules only while Island is open",isOn:$openOnly)
                Stepper("Snooze for \(snoozeMinutes) minutes",value:$snoozeMinutes,in:1...120)
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
                Toggle("Use Island’s volume and brightness indicators",isOn:$hud).help("Show volume and brightness changes in Island instead of the standard macOS indicators. Requires Window and media controls access.")
                Button("Manage permissions…") { IslandSettingsController.shared.showPermissions(.accessibility) }
                Text("Set up access once in Permissions, then choose the features you want here.").foregroundStyle(.secondary)
            }
            Section("Battery") { IslandPowerSwitch();Toggle("Show battery in Island",isOn:$battery); Text("The battery pop-up follows system appearance and uses native glass where macOS supports it.").foregroundStyle(.secondary) }
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
            Section("Help") { Button("Help & Tips") { IslandSettingsNavigation.shared.selected="Help & Tips" };Button("Island guide & diagnostics") { help=true };Button("Updates & installation preferences") { IslandSettingsNavigation.shared.selected="Updates" } }
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
