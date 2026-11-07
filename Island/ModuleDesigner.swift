import SwiftUI
import Defaults

struct IslandModuleDesigner:View {
    @ObservedObject private var modules=IslandModuleStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("island.designer.selected") private var selectedID=""
    @AppStorage("island.designer.inspector") private var inspecting=false
    @AppStorage("island.timer.work") private var workMinutes=25.0
    @AppStorage("island.weather.city") private var city=""
    @AppStorage("island.weather.fahrenheit") private var fahrenheit=false
    @State private var query=""
    @State private var previousLayout:IslandModulePreferences?
    @State private var feedback="Changes apply instantly. Preview content is illustrative."
    @State private var hideTargeted=false
    @State private var help=false
    var selected:NotchViews { NotchViews(rawValue:selectedID) ?? modules.defaultModule }
    var enabled:Bool { modules.enabled.contains(selected) }
    private var library:[NotchViews] {
        let main:[NotchViews]=[.dashboard,.home,.shelf,.focus,.notes]
        return (main+NotchViews.allCases.filter { !main.contains($0) }).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("Arrange your Island").font(.title2.weight(.semibold))
                Spacer()
                Menu("Layouts") { ForEach(["Minimal","Work","Everything"],id:\.self) { name in Button(name) { change { modules.profile(name) };feedback=name+" layout applied." } } }
                Button("Undo") { if let previousLayout { modules.restore(previousLayout);self.previousLayout=nil;feedback="Previous module layout restored." } }.disabled(previousLayout == nil).help("Undo the last module layout change")
            }
            HStack(spacing:14) {
                Label("Drag to add",systemImage:"hand.draw")
                Label("Drag icons to arrange",systemImage:"arrow.left.arrow.right")
                Label("Click for settings",systemImage:"cursorarrow.click")
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)

            IslandModulePreview(modules:modules.enabled,selected:selected,focusMinutes:workMinutes,weatherCity:city,fahrenheit:fahrenheit,onSelect:inspect,onDrop:drop)
                .frame(maxWidth:680,alignment:.leading)
                .animation(reduceMotion ? nil : .snappy(duration:0.18),value:modules.preferences)

            HStack(alignment:.center,spacing:10) {
                VStack(alignment:.leading,spacing:2) {
                    Text("Previewing "+selected.title+(enabled ? "" : " · Hidden")).font(.caption.weight(.medium))
                    Text("The first five icons appear in the bar. Others are in More.").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength:4)
                Label("Drop here to hide",systemImage:"eye.slash")
                    .font(.caption).padding(.horizontal,10).padding(.vertical,8)
                    .background(hideTargeted ? Color.red.opacity(0.12) : Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                    .overlay { RoundedRectangle(cornerRadius:10).strokeBorder(hideTargeted ? Color.red : Color.secondary.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[4])) }
                    .dropDestination(for:IslandModuleTransfer.self) { values,_ in guard values.count == 1 else { return false };return hide(values[0].module) } isTargeted: { hideTargeted=$0 }
                    .help("Hiding keeps the module’s data. You can also turn it off in its settings.")
            }
            Text(feedback).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:16,alignment:.leading)
            Divider()
            if inspecting { inspector } else { moduleLibrary }
        }.padding(16)
    }
    private var moduleLibrary:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text("All modules").font(.headline)
                Spacer()
                Button("How it works",systemImage:"questionmark.circle") { help.toggle() }.font(.caption).buttonStyle(.plain)
                    .popover(isPresented:$help) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Make it yours").font(.headline)
                            Text("1. Drag a card onto the black preview to add its module.")
                            Text("2. Drop onto an icon’s left or right half to place it before or after. More contains overflow modules.")
                            Text("3. Click a card or icon to see its settings below the preview.")
                            Text("To hide a module, drop its icon on Drop here to hide, or use Show in Island. Earlier and Later buttons also change the order without dragging.")
                            Text("Changes are saved immediately. Undo restores your previous layout. Preview content never starts a timer, camera or connection.").foregroundStyle(.secondary)
                        }.font(.callout).padding(20).frame(width:330)
                    }
            }
            TextField("Find a module",text:$query).textFieldStyle(.roundedBorder).accessibilityLabel("Find a module")
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:138),spacing:9)],spacing:9) {
                    ForEach(library) { module in
                        Button { inspect(module) } label: {
                            HStack(spacing:9) {
                                Image(systemName:module.icon).font(.system(size:19)).foregroundStyle(.blue).frame(width:25)
                                Text(module.title).font(.system(size:12,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                Image(systemName:modules.enabled.contains(module) ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(modules.enabled.contains(module) ? .green : .secondary)
                            }.padding(11).frame(maxWidth:.infinity,minHeight:57,alignment:.leading)
                                .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                                .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.07),lineWidth:1) }
                                .contentShape(RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain)
                        .help(IslandModuleGuide.description(module)+" Drag onto the preview to add; click to configure.")
                        .accessibilityLabel(module.title+(modules.enabled.contains(module) ? ", added. " : ", hidden. ")+"Click for settings. You can enable it there without dragging.")
                        .draggable(IslandModuleTransfer(module:module)) { Label(module.title,systemImage:module.icon).padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) }
                    }
                }
                if library.isEmpty { Text("No matching modules.").foregroundStyle(.secondary).padding();Button("Clear search") { query="" } }
            }.frame(maxHeight:.infinity)
        }
    }
    private var inspector:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Button { inspecting=false } label: { Label("All modules",systemImage:"chevron.left") }.buttonStyle(.plain).foregroundStyle(.blue)
                Spacer();Label(selected.title,systemImage:selected.icon).font(.headline)
            }
            HStack {
                Toggle("Show in Island",isOn:Binding(get:{ enabled },set:{ wanted in if wanted { _=drop(selected,nil,false) } else { _=hide(selected) } })).toggleStyle(.switch).disabled(enabled && modules.enabled.count == 1)
                Spacer()
                Button(modules.defaultModule == selected ? "Starts here" : "Open by default") { change { modules.setDefault(selected) };feedback=selected.title+" opens by default." }.disabled(!enabled || modules.defaultModule == selected)
            }
            if let index=modules.enabled.firstIndex(of:selected) {
                HStack { Text("Position \(index+1)"+(index<5 ? " · In the bar" : " · In More")).font(.caption).foregroundStyle(.secondary);Spacer();Button("Earlier") { shift(-1) }.disabled(index == 0);Button("Later") { shift(1) }.disabled(index == modules.enabled.count-1) }
            } else { Text("Hidden modules keep their data. Turn on Show in Island to add this one.").font(.caption).foregroundStyle(.secondary) }
            IslandModuleInspector(module:selected).id(selected).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private func inspect(_ module:NotchViews) { selectedID=module.rawValue;inspecting=true }
    private func change(_ action:()->Void) {
        let before=modules.preferences;action()
        if before != modules.preferences { previousLayout=before }
    }
    private func drop(_ module:NotchViews,_ target:NotchViews?,_ after:Bool)->Bool {
        let wasVisible=modules.enabled.contains(module)
        change { _=modules.place(module,relativeTo:target,after:after) }
        inspect(module)
        let inMore=(modules.enabled.firstIndex(of:module) ?? 0)>=5
        feedback=module.title+(wasVisible ? " arranged" : " added")+(inMore ? " in More." : " in the bar.")
        if module == .usage && !wasVisible { feedback += " Local app-use recording is now on." }
        return true
    }
    private func hide(_ module:NotchViews)->Bool {
        guard modules.enabled.contains(module) else { return false }
        guard modules.enabled.count>1 else { feedback="Keep at least one module in Island.";return false }
        change { modules.setEnabled(module,false) };feedback=module.title+" hidden. Its data is kept.";return true
    }
    private func shift(_ delta:Int) {
        guard let index=modules.enabled.firstIndex(of:selected),modules.enabled.indices.contains(index+delta) else { return }
        _=drop(selected,modules.enabled[index+delta],delta>0)
    }
}

struct IslandModuleInspector:View {
    let module:NotchViews
    @AppStorage("island.weather.city") private var city=""
    @AppStorage("island.weather.fahrenheit") private var fahrenheit=false
    @AppStorage("island.devices.alerts") private var deviceAlerts=false
    @AppStorage("island.devices.threshold") private var threshold=20
    @AppStorage("island.code.provider") private var codeProvider="GitHub"
    @AppStorage("island.code.repository") private var repository=""
    @AppStorage("island.code.reviewer") private var reviewer=""
    @AppStorage("island.code.jiraHost") private var jiraHost=""
    @AppStorage("island.code.email") private var email=""
    @AppStorage("island.code.jql") private var jql="assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"
    @AppStorage("island.translate.provider") private var translationProvider="Ollama"
    @AppStorage("island.translate.model") private var localModel="llama3.2"
    @AppStorage("island.translate.openaiModel") private var cloudModel=""
    @AppStorage("island.translate.language") private var language="English"
    @Default(.boringShelf) private var trayDrop
    @Default(.openShelfByDefault) private var openTray
    @State private var sheet:Sheet?
    enum Sheet:String,Identifiable { case weather,connections;var id:String { rawValue } }
    var body:some View {
        Group {
            switch module {
            case .dashboard:IslandDashboardSettings()
            case .home:IslandMediaSettings()
            case .focus:IslandFocusSettings()
            case .health:IslandWellbeingSettings()
            case .windows:IslandWindowSettings()
            case .agents:IslandBridgeSettings()
            default:options
            }
        }.sheet(item:$sheet) { destination in
            VStack(alignment:.leading,spacing:12) {
                HStack { Text(destination == .weather ? "Weather" : "Account connections").font(.headline);Spacer();Button("Done") { sheet=nil } }.padding(.horizontal,18).padding(.top,16)
                if destination == .weather { ScrollView { IslandWeatherView().padding(18) } } else { IslandConnectionsSettings(provider:module == .translation ? "OpenAI" : codeProvider) }
            }.frame(width:560,height:530)
        }
    }
    private var options:some View {
        Form {
            Section(module.title) { Text(IslandModuleGuide.description(module)).foregroundStyle(.secondary) }
            switch module {
            case .shelf:
                Section("File Tray") { Toggle("Accept drops over the closed Island",isOn:$trayDrop);Toggle("Open File Tray when it contains files",isOn:$openTray);Text("Your files stay in their original locations. Hiding the tray keeps its saved items.").font(.caption).foregroundStyle(.secondary) }
            case .weather:
                Section("Your forecast") { TextField("City",text:$city);Toggle("Use Fahrenheit",isOn:$fahrenheit);Button("Background and forecast…") { sheet = .weather };Text("Changing these settings doesn’t send a search. Choose Get forecast when you’re ready.").font(.caption).foregroundStyle(.secondary) }
            case .devices:
                Section("Low-battery alerts") { Toggle("Notify when a device battery is low",isOn:$deviceAlerts);Stepper("Notify at \(threshold)%",value:$threshold,in:5...50,step:5);permission(.bluetooth);permission(.notifications) }
            case .code:
                Section("Review lists") {
                    Picker("Provider",selection:$codeProvider) { ForEach(["GitHub","GitLab","Bitbucket","Jira"],id:\.self) { Text($0).tag($0) } }
                    if codeProvider == "Jira" { TextField("your-site.atlassian.net",text:$jiraHost);TextField("Account email",text:$email);TextField("JQL",text:$jql) }
                    else { TextField("workspace/repository",text:$repository);TextField("Requested reviewer",text:$reviewer) }
                    Button("Manage account tokens…") { sheet = .connections };Text("Lists load only when you choose Refresh in Code Hosting.").font(.caption).foregroundStyle(.secondary)
                }
            case .translation:
                Section("Translation") { Picker("Provider",selection:$translationProvider) { Text("Local Ollama").tag("Ollama");Text("OpenAI").tag("OpenAI") };TextField("Model",text:translationProvider == "OpenAI" ? $cloudModel : $localModel);TextField("Translate into",text:$language);if translationProvider == "OpenAI" { Button("Manage API key…") { sheet = .connections };Text("OpenAI is optional and billed separately. Nothing is sent until you press Translate.").font(.caption).foregroundStyle(.secondary) } }
            case .calendar,.day:Section("Your calendar") { permission(.calendar);Text("Your schedule is read only after you allow access.").font(.caption).foregroundStyle(.secondary) }
            case .tasks:Section("Your tasks") { permission(.reminders);Text("Task trash can be restored from Tasks for 30 days.").font(.caption).foregroundStyle(.secondary) }
            case .mirror:Section("Camera") { permission(.camera);Text("This preview never turns the camera on. Start and stop the camera from Mirror in your Island.").font(.caption).foregroundStyle(.secondary) }
            case .launcher:Section("Your shortcuts") { IslandLauncherView() }
            case .inbox:Section("Alerts") { permission(.notifications);Button("Manage forwarded alerts…") { IslandSettingsNavigation.shared.selected="Agents & Inbox" };Text("Only Island’s alerts and notices you forward appear here.").font(.caption).foregroundStyle(.secondary) }
            case .usage:Section("Local and optional") { Text("App names and active-use counters are stored on this Mac while Show in Island is on. Hiding this module stops recording. Categorize apps and manage history in Screen Time.").foregroundStyle(.secondary) }
            case .notes:Section("Automatically saved") { Text("Write and organize notes in your Island. Notes save as you type; deleted notes stay in recoverable trash for 30 days. Hiding this module does not delete them.").foregroundStyle(.secondary) }
            case .system:Section("Automatic readings") { Text("CPU and memory readings update while System Monitor is open. There are no additional settings for this module.").foregroundStyle(.secondary) }
            case .files:Section("Choose files when needed") { Text("File actions are chosen for each selection in your Island. Your preview never opens, moves, converts or deletes files. There are no additional global settings.").foregroundStyle(.secondary) }
            default:EmptyView()
            }
        }.formStyle(.grouped)
        .onChange(of:deviceAlerts) { IslandDevices.shared.configure(IslandModuleStore.shared.enabled.contains(.devices)) }
    }
    private func permission(_ key:IslandPermission)->some View { Button("Manage "+key.title+" access…") { IslandSettingsController.shared.showPermissions(key) } }
}
