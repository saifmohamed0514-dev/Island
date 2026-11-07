import SwiftUI
import Defaults

struct IslandModuleDesigner:View {
    @ObservedObject private var modules=IslandModuleStore.shared
    @ObservedObject private var canvas=IslandCanvasStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("island.designer.selected") private var selectedID=""
    @AppStorage("island.designer.inspector") private var inspecting=false
    @AppStorage("island.timer.work") private var workMinutes=25.0
    @AppStorage("island.weather.city") private var city=""
    @AppStorage("island.weather.fahrenheit") private var fahrenheit=false
    @State private var query=""
    @State private var previousLayout:IslandDesignerSnapshot?
    @State private var feedback="Drag a card into a space inside the notch."
    @State private var removeTargeted=false
    @State private var help=false
    var selected:NotchViews { NotchViews(rawValue:selectedID) ?? canvas.preferences.modules.first ?? .home }
    var inLayout:Bool { canvas.preferences.modules.contains(selected) }
    var moduleEnabled:Bool { modules.enabled.contains(selected) }
    private var library:[NotchViews] {
        let main:[NotchViews]=[.home,.shelf,.focus,.notes,.dashboard]
        return (main+NotchViews.allCases.filter { !main.contains($0) }).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("Build your Island").font(.title2.weight(.semibold));Spacer()
                Menu("Layouts") { ForEach(["Music & focus","Work","Simple"],id:\.self) { name in Button(name) { change { canvas.template(name) };feedback=name+" layout applied to Island." } } }
                Button("Undo") { if let previousLayout { modules.restore(previousLayout.modules);canvas.restore(previousLayout.canvas);self.previousLayout=nil;feedback="Previous layout restored." } }.disabled(previousLayout == nil)
            }
            HStack(spacing:14) { Label("Drop into a space",systemImage:"hand.draw");Label("Drag blocks to swap",systemImage:"arrow.left.arrow.right");Label("Click for settings",systemImage:"cursorarrow.click") }.font(.caption).foregroundStyle(.secondary)
            IslandModulePreview(modules:modules.enabled,slots:canvas.preferences.slots,selected:selected,focusMinutes:workMinutes,weatherCity:city,fahrenheit:fahrenheit,onSelect:inspect,onDrop:drop)
                .frame(maxWidth:680,alignment:.leading).animation(reduceMotion ? nil : .snappy(duration:0.18),value:canvas.preferences)
            HStack(spacing:8) {
                Toggle("Use this layout in Island",isOn:Binding(get:{ canvas.preferences.enabled },set:{ value in change { canvas.setEnabled(value) };feedback=value ? "Your layout is now Island’s Dashboard." : "Original Dashboard restored. Your arrangement is saved." })).toggleStyle(.switch).font(.caption)
                Spacer(minLength:0)
                Label("Drop to remove",systemImage:"minus.circle").font(.caption).padding(8)
                    .background(removeTargeted ? Color.red.opacity(0.12) : Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                    .overlay { RoundedRectangle(cornerRadius:10).strokeBorder(removeTargeted ? Color.red : Color.secondary.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[4])) }
                    .dropDestination(for:IslandModuleTransfer.self) { values,_ in guard values.count == 1 else { return false };return remove(values[0].module) } isTargeted: { removeTargeted=$0 }
                    .help("Remove a block from this layout. The module and its data are kept.")
            }
            Text(feedback+" Preview content is illustrative.").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:16,alignment:.leading)
            HStack(spacing:10) {
                Picker("Module settings",selection:Binding(get:{ selected },set:inspect)) { ForEach(NotchViews.allCases) { module in Text(module.title).tag(module) } }.pickerStyle(.menu)
                Button("Open settings") { inspect(selected) }
            }.help("Choose any module, including File Tray, then open its settings below.")
            Divider()
            moduleLibrary
        }.padding(16)
        .sheet(isPresented:$inspecting) { inspector.padding(18).frame(width:560,height:540) }
    }
    private var moduleLibrary:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text("Modules to add").font(.headline);Spacer()
                Button("How it works",systemImage:"questionmark.circle") { help.toggle() }.font(.caption).buttonStyle(.plain)
                    .popover(isPresented:$help) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Build it right here").font(.headline)
                            Text("1. Drag a module card into a space inside the black notch preview.")
                            Text("2. Drag an existing block to another space to swap positions. A new module replaces the block you drop it onto.")
                            Text("3. Click a block for its settings. Use the position buttons if you prefer not to drag.")
                            Text("The same four positions become your real Island’s Dashboard. Click a real block for full controls, then use the grid button to return to your layout.")
                            Text("Removing a block keeps its module and data. Use Enable module to turn a feature off completely. Undo restores the previous arrangement.").foregroundStyle(.secondary)
                        }.font(.callout).padding(20).frame(width:340)
                    }
            }
            TextField("Find a module",text:$query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:138),spacing:9)],spacing:9) {
                    ForEach(library) { module in
                        Button { inspect(module) } label: {
                            HStack(spacing:9) { Image(systemName:module.icon).font(.system(size:19)).foregroundStyle(.blue).frame(width:25);Text(module.title).font(.system(size:12,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading);Image(systemName:canvas.preferences.modules.contains(module) ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(canvas.preferences.modules.contains(module) ? .green : .secondary) }
                                .padding(11).frame(maxWidth:.infinity,minHeight:57,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)).overlay { RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.07),lineWidth:1) }.contentShape(RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).help(IslandModuleGuide.description(module)+" Drag into a space inside the preview; click for settings.")
                            .accessibilityLabel(module.title+". Click for settings or drag into the preview.")
                            .draggable(IslandModuleTransfer(module:module)) { Label(module.title,systemImage:module.icon).padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) }
                    }
                }
                if library.isEmpty { Text("No matching modules.").foregroundStyle(.secondary).padding();Button("Clear search") { query="" } }
            }.frame(maxHeight:.infinity)
        }
    }
    private var inspector:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Image(systemName:selected.icon).foregroundStyle(.blue)
                Picker("Module",selection:Binding(get:{ selected },set:{ selectedID=$0.rawValue })) { ForEach(NotchViews.allCases) { module in Text(module.title).tag(module) } }.font(.headline)
                Spacer();Button("Done") { inspecting=false }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Toggle("Show in layout",isOn:Binding(get:{ inLayout },set:{ wanted in if wanted { _=drop(selected,canvas.preferences.slots.firstIndex(of:nil) ?? 0) } else { _=remove(selected) } })).toggleStyle(.switch)
                Spacer()
                Toggle("Enable module",isOn:Binding(get:{ moduleEnabled },set:{ value in change { modules.setEnabled(selected,value) } })).toggleStyle(.switch).disabled(moduleEnabled && modules.enabled.count == 1)
            }.font(.caption)
            HStack {
                Text("Position").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<4,id:\.self) { index in Button(IslandCanvasPreferences.title(index)) { _=drop(selected,index) }.font(.caption).disabled(canvas.preferences.slots[index] == selected) }
            }
            IslandModuleInspector(module:selected).id(selected).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private func inspect(_ module:NotchViews) { selectedID=module.rawValue;inspecting=true }
    private func change(_ action:()->Void) {
        let before=IslandDesignerSnapshot(modules:modules.preferences,canvas:canvas.preferences);action()
        if before.modules != modules.preferences || before.canvas != canvas.preferences { previousLayout=before }
    }
    private func drop(_ module:NotchViews,_ index:Int)->Bool {
        guard (0..<4).contains(index) else { return false }
        let previous=canvas.preferences.slots[index],wasInLayout=canvas.preferences.modules.contains(module),wasEnabled=modules.enabled.contains(module)
        change { canvas.place(module,at:index) };selectedID=module.rawValue
        feedback=module.title+" placed "+IslandCanvasPreferences.title(index).lowercased()+". Layout applied to Island."
        if !wasInLayout,let previous,previous != module { feedback=module.title+" replaced "+previous.title+" in this layout. Both modules keep their data." }
        if module == .usage && !wasEnabled && modules.enabled.contains(module) { feedback += " Local app-use recording is now on." }
        return true
    }
    private func remove(_ module:NotchViews)->Bool {
        guard canvas.preferences.modules.contains(module) else { return false }
        change { canvas.remove(module) };feedback=module.title+" removed from this layout. Its module and data are kept.";return true
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
            case .usage:Section("Local and optional") { Text("App names and active-use counters are stored on this Mac while Enable module is on. Removing its block only changes the layout; turning Enable module off stops recording. Categorize apps and manage history in Screen Time.").foregroundStyle(.secondary) }
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
