import SwiftUI

struct IslandGuideTopic:Identifiable {
    let id:String
    let title:String
    let summary:String
    let steps:[String]
    var note:String? = nil
    func matches(_ query:String)->Bool {
        let words=query.split(whereSeparator: { $0.isWhitespace })
        let content=([title,summary]+steps+[note ?? ""]).joined(separator:" ")
        return words.allSatisfy { content.localizedCaseInsensitiveContains(String($0)) }
    }
}
enum IslandGuideCatalog {
    static let pages:[IslandGuideTopic]=[
        .init(id:"Overview",title:"Start with your everyday tools",summary:"An overview of your Island and shortcuts to its main settings.",steps:["Choose Modules to arrange your Island.","Use Permissions to set up only the features you need.","Replay Set up Island for the full practice tutorial."]),
        .init(id:"Permissions",title:"Give each feature the access it needs",summary:"Choose features, then approve their own macOS requests one at a time.",steps:["Select the features you want and choose Set up selected.","Approve the macOS prompt yourself. Some controls need a switch in System Settings.","Return to Island; it checks access automatically. Check access retries the status check."],note:"macOS keeps privacy approvals separate. One Touch ID prompt cannot approve every permission."),
        .init(id:"Modules",title:"Build your layout",summary:"Modules are the tools inside Island. The preview changes your real layout.",steps:["Drag a card into one of the four spaces in the black preview.","Drag a block onto another space to swap. Click a block to open its settings.","Use Layouts to save your arrangement or switch to another one. Undo brings back the previous arrangement."],note:"Removing a block keeps its module and data. Enable module controls whether the feature itself runs."),
        .init(id:"Dashboard",title:"Widgets and automatic layouts",summary:"Choose four compact widgets and optional changes based on time or system Focus.",steps:["Choose a widget for each slot. Add Dashboard as a module block to use these classic widgets.","System Focus follows the on/off status shared by macOS; it is separate from Island’s focus timer.","The daily schedule switches between Work and Minimal at the times you choose."],note:"Automatic layout changes can replace a manually chosen layout at the next schedule or Focus change."),
        .init(id:"Live Activities",title:"Updates while Island is closed",summary:"Live Activities are small updates beside the camera, such as a timer or song.",steps:["Enable the activities you want to see.","Turn on rotation to cycle through available activities every six seconds.","Use Media sources to hide an app’s compact activity without removing playback controls."],note:"The relevant module must be enabled. Volume, battery and approval notices can temporarily take priority."),
        .init(id:"Displays",title:"Choose where Island appears",summary:"Use the top center of one display or every connected display.",steps:["Choose Show on every display, or select a preferred display.","Follow the active display moves Island to the screen you are using.","On displays without a notch, match the menu bar or choose a collapsed height."],note:"A preferred display and display following are available when Show on every display is off."),
        .init(id:"Behavior",title:"Make everyday actions feel right",summary:"Control startup, hover, haptics, keyboard shortcuts and privacy.",steps:["Open at login keeps Island available after you sign in.","Hover delay is how long your pointer must rest on Island before it opens.","Click a shortcut recorder, then press your preferred key combination. Snooze hides Island temporarily."],note:"Haptics are gentle trackpad feedback on supported hardware. Pin keeps Island open until you unpin it."),
        .init(id:"Focus & Sounds",title:"Set time aside",summary:"Choose timer lengths, saved presets, work/break cycles and completion sounds.",steps:["Pause the timer before dragging its ring to set a custom duration.","Add a preset for a duration you use often. Full ring duration sets the ring’s scale.","Choose a sound and Preview it. Ring until stopped repeats the completion sound until you choose Stop."],note:"Apply duration and reset replaces the current countdown. System Focus and Island’s timer are separate features."),
        .init(id:"Media",title:"Choose your music player",summary:"Show real artwork and control playback in a supported app or browser.",steps:["Choose Now Playing for supported apps and browsers, or select a specific player.","Play something in that app, then open Now Playing in Island.","Use Manage player permissions if Music or Spotify needs Automation approval."],note:"Seeking and player volume depend on the chosen player. Idle playback is shown as Not Playing."),
        .init(id:"Window Snapping",title:"Arrange windows with a drag",summary:"Snap a movable window to a half, corner or the available screen area.",steps:["Enable edge previews and allow Window and media controls in Permissions.","Drag a window by its title bar to a screen edge or corner.","Release when the preview shows the layout you want. Use Window Layouts for manual placement."],note:"Some apps have minimum window sizes. Full-screen windows cannot be tiled this way."),
        .init(id:"Wellbeing & Alerts",title:"Make room for small breaks",summary:"Set personal goals and optional water, movement and low-battery reminders.",steps:["Choose goals that suit your day.","Enable reminders and set their intervals and wind-down time.","Allow Notifications if you want macOS alerts. Island also keeps its own notices in Inbox."],note:"Wellbeing reminders need its module enabled. Accessory battery alerts need Bluetooth and a device that reports its level."),
        .init(id:"System Controls",title:"Battery and media overlays",summary:"Show your battery and let Island display volume and brightness changes.",steps:["Use Island’s volume and brightness indicators replaces the standard system HUDs. HUD means the indicator shown when a media key is pressed.","Set up Window and media controls in Permissions, then enable the overlays here.","Click the battery in Island for its pop-up. Enable power controls once if you want to change Low Power Mode."],note:"Low Power Mode can reduce background activity and performance to save energy. The power setup asks for administrator approval."),
        .init(id:"Connections",title:"Connect only what you use",summary:"Optional account tokens connect code services and translation providers.",steps:["Choose a provider and save its token or API key.","Enter the repository or model in that module’s settings.","Use Refresh or Translate in the module when you are ready."],note:"Tokens are stored in Keychain. OpenAI API use is billed separately; local Ollama needs a running server and installed model."),
        .init(id:"Agents & Inbox",title:"Bring local coding activity into Island",summary:"Show supported local AI sessions, individual approval requests and forwarded notices.",steps:["Prepare a private bridge folder, then install the example for your supported client.","Review and trust hooks in the client itself.","Respond to one request at a time in Island. Inbox contains Island’s alerts and explicitly forwarded notices."],note:"A connected folder is not proof that hooks are trusted. Ordinary ChatGPT web chats do not send local hook events."),
        .init(id:"Updates",title:"Choose when Island updates",summary:"Control automatic checks, downloads and installation timing.",steps:["Enable automatic checks only if you want them.","Choose how often to check and whether to download signed updates.","Choose installation on quit, while idle, or while idle at night."],note:"This local preview needs a published release channel before updates can arrive. An owner can connect one in the advanced section."),
        .init(id:"Language",title:"Choose your app language",summary:"Follow macOS or choose a supported Island language.",steps:["Select a language.","Restart Island to apply it. Your saved files, notes and timer are kept."],note:"Some detailed integration messages remain in English."),
        .init(id:"Help & Tips",title:"Find an answer when you need it",summary:"Short explanations and instructions for each page and module.",steps:["Search for a tool, an action or a word you do not recognize.","Open a topic to see its steps.","The question-mark button in Settings always opens help for the page you are on."]),
        .init(id:"About Island",title:"About this copy",summary:"Find the version, open-source credits and diagnostic summary.",steps:["Use Help & Tips for instructions, or replay the setup tutorial from Overview.","Copy a diagnostic summary when reporting an issue. It includes app, system and feature status, not your notes, files or account tokens."])
    ]
    static func page(_ route:String)->IslandGuideTopic {
        pages.first { $0.id == route } ?? pages[0]
    }
    static func module(_ module:NotchViews)->IslandGuideTopic {
        let steps:[String]
        switch module {
        case .dashboard:steps=["Pick widgets in Dashboard settings, or build your four-position layout in Modules.","Click a real block to open the tool. Use the grid button to return."]
        case .home:steps=["Start playback in a supported app, then open Now Playing in Island.","Use playback buttons and the progress bar when your player supports them. Choose a source in Media settings."]
        case .shelf:steps=["Drop files into File Tray or onto the closed Island when drops are enabled.","Select an item to preview, share or drag it into another app. Removing it from the tray keeps the original file."]
        case .focus:steps=["Pause, then drag the ring or use its arrow-key controls to choose a duration.","Start the timer. Save presets and choose sounds in Focus & Sounds."]
        case .notes:steps=["Create or choose a note, then type; changes save automatically.","Deleted notes can be restored from note trash for 30 days."]
        case .weather:steps=["Enter your city and choose Get forecast.","Choose units and explore the hourly and seven-day forecasts. Background choices are in Weather settings."]
        case .health:steps=["Log water, movement or mindful moments as you go.","Choose goals and optional reminders in Wellbeing & Alerts."]
        case .system:steps=["Open System Monitor to see CPU, memory and storage readings.","CPU is processor activity. Memory is working RAM; storage is space on your disk."]
        case .usage:steps=["Enable this module to record local active-app time and switch counts.","Choose a day, assign categories, or exclude apps in its settings. Disable the module to stop recording."]
        case .calendar:steps=["Allow Calendar access in Permissions.","Open Calendar to view and search upcoming events."]
        case .tasks:steps=["Allow Reminders access, then add or complete tasks in Island.","Removed tasks can be restored from task trash for 30 days."]
        case .day:steps=["Choose your day and wind-down settings.","Allow Calendar or Reminders to include events and due tasks in the timeline."]
        case .launcher:steps=["Add the apps or folders you want to keep close.","Click a bookmark to open it. Keep Awake temporarily prevents idle sleep until stopped."]
        case .code:steps=["Choose a provider and repository in this module’s settings.","Save an account token in Connections, then choose Refresh in Code Hosting."]
        case .translation:steps=["Choose local Ollama or OpenAI and enter an available model.","Enter text and a target language, then choose Translate. Only that action sends the text to your chosen provider."]
        case .devices:steps=["Allow Bluetooth access, then open the module for connected accessories.","Enable optional low-battery alerts and choose a threshold. Some accessories do not share battery levels."]
        case .windows:steps=["Allow Window and media controls in Permissions.","Choose a manual layout, or enable edge snapping and drag a window’s title bar to an edge."]
        case .files:steps=["Choose files, then select an archive, conversion or sharing action.","Choose a destination when asked. Check the selection before moving or converting files."]
        case .mirror:steps=["Allow Camera access, then choose Start mirror in your real Island.","Stop the preview when finished. Leaving the module stops the camera."]
        case .agents:steps=["Prepare the private bridge and review its hooks in your supported local coding client.","Open AI Coding to see sessions and approve or deny individual requests."]
        case .inbox:steps=["Open Inbox to review Island alerts or notices you explicitly forward.","Clear read notices when you no longer need them. Unrelated apps’ notifications are not imported."]
        }
        return .init(id:"module."+module.rawValue,title:module.title,summary:IslandModuleGuide.description(module),steps:steps)
    }
}

struct IslandGuideContent:View {
    let topic:IslandGuideTopic
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(topic.title).font(.headline)
            Text(topic.summary).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ForEach(Array(topic.steps.enumerated()),id:\.offset) { index,step in
                HStack(alignment:.top,spacing:10) {
                    Text("\(index+1)").font(.caption.weight(.semibold)).foregroundStyle(.blue).frame(width:22,height:22).background(.blue.opacity(0.1),in:Circle())
                    Text(step).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                }
            }
            if let note=topic.note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
        }.font(.callout).textSelection(.enabled)
    }
}
struct IslandPageHelp:View {
    let route:String
    @State private var open=false
    var body:some View {
        Button("Help for "+route,systemImage:"questionmark.circle") { open.toggle() }
            .labelStyle(.iconOnly).help("What this page does and how to use it")
            .popover(isPresented:$open) {
                ScrollView { IslandGuideContent(topic:IslandGuideCatalog.page(route)).padding(20) }.frame(width:390).frame(maxHeight:520)
            }
            .onChange(of:route) { open=false }
    }
}
struct IslandGuideDisclosure:View {
    let topic:IslandGuideTopic
    @State private var expanded=false
    var body:some View {
        DisclosureGroup(isExpanded:$expanded) {
            IslandGuideContent(topic:topic).padding(.vertical,8)
        } label: {
            Button { expanded.toggle() } label: { Text(topic.title).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel(topic.title+" instructions").accessibilityValue(expanded ? "Expanded" : "Collapsed")
        }
    }
}
struct IslandGuidanceSettings:View {
    @State private var query=""
    private var pages:[IslandGuideTopic] { IslandGuideCatalog.pages.filter { $0.id != "Help & Tips" && $0.matches(query) } }
    private var modules:[IslandGuideTopic] { NotchViews.allCases.map(IslandGuideCatalog.module).filter { $0.matches(query) } }
    var body:some View {
        Form {
            Section {
                Text("A little help, when you need it.").font(.title2.weight(.semibold))
                TextField("Search help",text:$query).textFieldStyle(.roundedBorder).accessibilityLabel("Search Island instructions")
                Text("The question-mark button in each Settings page explains its controls. Hover over a control for a quick tip.").font(.callout).foregroundStyle(.secondary)
            }
            if pages.isEmpty && modules.isEmpty {
                ContentUnavailableView.search(text:query)
            }
            if !pages.isEmpty { Section("Settings") { ForEach(pages) { topic in IslandGuideDisclosure(topic:topic) } } }
            if !modules.isEmpty { Section("Modules") { ForEach(modules) { topic in IslandGuideDisclosure(topic:topic) } } }
        }.formStyle(.grouped)
    }
}
