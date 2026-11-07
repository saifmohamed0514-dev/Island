import SwiftUI
import Combine
import AppKit

@MainActor final class IslandAgentBridge:ObservableObject {
    static let shared = IslandAgentBridge()
    struct Event:Codable,Identifiable {
        var id:String; var nonce:String; var provider:String; var event:String; var session:String
        var time:Double; var expires:Double; var approval:Bool; var title:String; var message:String; var request:String; var resolution:String?
        var pending:Bool { approval && expires > Date().timeIntervalSince1970 }
        var providerName:String { switch provider { case "chatgpt":return "ChatGPT Work";case "codex":return "Codex";case "claude":return "Claude Code";case "cursor":return "Cursor";default:return "Forwarded" } }
        var notice:Bool { provider == "relay" || event == "Notification" }
    }
    @Published var events:[Event] = []
    @Published var folderName:String?
    @Published var error:String?
    private var root:URL?
    private var task:Task<Void,Never>?
    init() { folderName = UserDefaults.standard.string(forKey:"island.bridge.folderName") }
    var sessions:[Event] {
        let grouped = Dictionary(grouping:events.filter { !$0.notice },by:{ $0.provider+":"+($0.session.isEmpty ? $0.id : $0.session) })
        return grouped.values.compactMap { group in group.first(where: { $0.pending }) ?? group.first }.sorted { $0.time > $1.time }
    }
    var pending:[Event] { events.filter(\.pending) }
    var notices:[Event] { events.filter(\.notice) }
    func start(_ enabled:Bool) {
        task?.cancel(); task = nil
        if let root { root.stopAccessingSecurityScopedResource(); self.root = nil }
        guard enabled, let data = UserDefaults.standard.data(forKey:"island.bridge.bookmark") else { return }
        do {
            var stale = false; let url = try URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
            guard url.startAccessingSecurityScopedResource() else { error = "Choose the bridge folder again to restore access."; return }
            root = url; folderName = url.lastPathComponent
            task = Task { [weak self] in while !Task.isCancelled { self?.refresh(); try? await Task.sleep(for:.seconds(1)) } }
        } catch { self.error = "Bridge folder is unavailable. Choose it again." }
    }
    func choose() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.message = "Choose a private, local folder for agent hooks. Avoid cloud-synced folders: events can include tool arguments."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource(); defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            guard let executable = Bundle.main.url(forResource:"IslandBridge",withExtension:nil) else { error = "Bridge helper is missing from this build."; return }
            let output = folder.appendingPathComponent("IslandBridge")
            if FileManager.default.fileExists(atPath:output.path) {
                let readme=folder.appendingPathComponent("READ-ME.txt")
                guard let size=try? readme.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<65536,let text=try? String(contentsOf:readme,encoding:.utf8),text.hasPrefix("Island hook bridge") else { error="This folder contains another IslandBridge file. Choose an empty private folder to avoid overwriting it.";return }
                let bookmark=try folder.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
                UserDefaults.standard.set(bookmark,forKey:"island.bridge.bookmark");UserDefaults.standard.set(folder.lastPathComponent,forKey:"island.bridge.folderName");folderName=folder.lastPathComponent;error=nil
                start(IslandModuleStore.shared.enabled.contains(.agents) || IslandModuleStore.shared.enabled.contains(.inbox));return
            }
            try FileManager.default.copyItem(at:executable,to:output); try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:output.path)
            let bookmark = try folder.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
            UserDefaults.standard.set(bookmark,forKey:"island.bridge.bookmark")
            try writeSamples(folder:folder,executable:output)
            error = nil; folderName = folder.lastPathComponent; UserDefaults.standard.set(folderName,forKey:"island.bridge.folderName"); start(IslandModuleStore.shared.enabled.contains(.agents) || IslandModuleStore.shared.enabled.contains(.inbox))
        } catch { self.error = "Couldn’t prepare this folder. Choose a writable local folder." }
    }
    private func writeSamples(folder:URL,executable:URL) throws {
        func quote(_ s:String)->String { "'"+s.replacingOccurrences(of:"'",with:"'\"'\"'")+"'" }
        let base = quote(executable.path)+" --directory "+quote(folder.path)
        var hooks:[String:Any] = [:]
        for event in ["SessionStart","UserPromptSubmit","PermissionRequest","Notification","Stop","SessionEnd"] { hooks[event] = [["hooks":[["type":"command","command":base+" --provider claude --event "+event,"timeout":60]]]] }
        let claude = try JSONSerialization.data(withJSONObject:["hooks":hooks],options:[.prettyPrinted,.sortedKeys]); try claude.write(to:folder.appendingPathComponent("claude-hooks.example.json"),options:.atomic)
        var openAIHooks:[String:Any] = [:]
        for event in ["SessionStart","UserPromptSubmit","PermissionRequest","Stop","Interrupt","SessionEnd"] {
            openAIHooks[event] = [["hooks":[["type":"command","command":base+" --provider chatgpt --event "+event,"timeout":60]]]]
        }
        let openAI = try JSONSerialization.data(withJSONObject:["description":"Island session activity and one-request approvals for ChatGPT Work and Codex.","hooks":openAIHooks],options:[.prettyPrinted,.sortedKeys])
        try openAI.write(to:folder.appendingPathComponent("chatgpt-codex-hooks.example.json"),options:.atomic)
        let plugin = folder.appendingPathComponent("island-chatgpt-plugin",isDirectory:true)
        let hookFolder = plugin.appendingPathComponent("hooks",isDirectory:true)
        try FileManager.default.createDirectory(at:hookFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try openAI.write(to:hookFolder.appendingPathComponent("hooks.json"),options:.atomic)
        let manifest:[String:Any] = ["name":"island","version":"2.3.0","description":"Local Island activity and explicit one-request approvals.","extensions":["com.openai":["hooks":"./hooks/hooks.json"]]]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:plugin.appendingPathComponent("plugin.json"),options:.atomic)
        var cursor:[String:Any] = [:]
        for event in ["sessionStart","beforeShellExecution","beforeMCPExecution","afterShellExecution","stop","sessionEnd"] { cursor[event] = [["command":base+" --provider cursor --event "+event]] }
        let data = try JSONSerialization.data(withJSONObject:["version":1,"hooks":cursor],options:[.prettyPrinted,.sortedKeys]); try data.write(to:folder.appendingPathComponent("cursor-hooks.example.json"),options:.atomic)
        let readme = "Island hook bridge\n\nExamples only: merge the relevant hooks into your ChatGPT/Codex or Claude/Cursor configuration. For ChatGPT Work and Codex, review and trust the hook definitions in the client before enabling them. A plugin folder is also included. No separate OpenAI API key is needed. No existing client settings were changed. Review the official client documentation and preserve your existing hooks. Before-shell Cursor hooks ask Island about every matching shell command; timeout declines. Claude PermissionRequest timeouts retain the original client prompt. Allow applies to one request only. Events may contain sensitive tool arguments; keep this folder private and unsynced. Generated events expire after one day. To disconnect, remove the hooks in your client's settings.\n\nhttps://learn.chatgpt.com/docs/hooks\nhttps://code.claude.com/docs/en/hooks\nhttps://cursor.com/docs/hooks\n"
        try readme.write(to:folder.appendingPathComponent("READ-ME.txt"),atomically:true,encoding:.utf8)
    }
    func refresh() {
        guard let root else { return }
        let directory = root.appendingPathComponent("events",isDirectory:true)
        guard let files = try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey]) else { events = []; return }
        let now = Date().timeIntervalSince1970
        events = files.filter { $0.lastPathComponent.hasSuffix(".island-event.json") }.prefix(500).compactMap { url in
            guard let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 1_048_576, let data = try? Data(contentsOf:url), let event = try? JSONDecoder().decode(Event.self,from:data), UUID(uuidString:event.id) != nil, UUID(uuidString:event.nonce) != nil, event.time.isFinite, event.expires.isFinite, event.time <= now+60, now-event.time < 86400 else { return nil }; return event
        }.sorted { $0.time > $1.time }
    }
    func decide(_ event:Event,allow:Bool) {
        guard event.pending, let root else { return }
        do {
            let folder = root.appendingPathComponent("decisions",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data = try JSONSerialization.data(withJSONObject:["id":event.id,"nonce":event.nonce,"allow":allow])
            let file = folder.appendingPathComponent(event.id+".json"); try data.write(to:file,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            error = nil
        } catch { self.error = "Couldn’t return this decision. Review it in the original client." }
    }
    func updateFiles() {
        guard let root else { error="Enable AI Coding or Inbox, then reconnect your bridge folder.";return }
        do {
            guard let helper=Bundle.main.url(forResource:"IslandBridge",withExtension:nil) else { return }
            let backup=root.appendingPathComponent("Island Backup-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            for name in ["IslandBridge","claude-hooks.example.json","cursor-hooks.example.json","chatgpt-codex-hooks.example.json","READ-ME.txt","island-chatgpt-plugin"] {
                let file=root.appendingPathComponent(name);if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.moveItem(at:file,to:backup.appendingPathComponent(name)) }
            }
            let output=root.appendingPathComponent("IslandBridge");try FileManager.default.copyItem(at:helper,to:output);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:output.path);try writeSamples(folder:root,executable:output)
            error="Updated the generated files. Previous files are preserved in "+backup.lastPathComponent+". Review changed hooks in each client before trusting them."
        } catch { self.error="Couldn’t finish updating the bridge files. Previous files remain in the backup folder." }
    }
    func reveal() { if let root { NSWorkspace.shared.activateFileViewerSelecting([root]) } }
    func disconnect() { start(false); UserDefaults.standard.removeObject(forKey:"island.bridge.bookmark"); UserDefaults.standard.removeObject(forKey:"island.bridge.folderName"); folderName = nil; events = [] }
}
struct IslandBridgeSettings:View {
    @ObservedObject var bridge = IslandAgentBridge.shared
    var body:some View {
        Form {
            Section("Local agent bridge") {
                Text("Connect ChatGPT Work, Codex, Claude Code or Cursor using local hooks. Island lists real session events and lets you approve one pending request at a time.")
                HStack { Button("Prepare a bridge folder…") { bridge.choose() }; if bridge.folderName != nil { Button("Update bridge files") { bridge.updateFiles() };Button("Show folder") { bridge.reveal() };Button("Disconnect") { bridge.disconnect() } } }
                if let folder = bridge.folderName { LabeledContent("Folder",value:folder) }
                Text("Setup exports a helper and example configurations to a folder you choose. It never edits your existing ChatGPT, Codex, Claude or Cursor settings. Keep event files in a private folder outside cloud syncing.").font(.caption).foregroundStyle(.secondary)
            }
            Section("ChatGPT and Codex") {
                Text("Your bridge folder includes a ChatGPT/Codex hook example and an Island plugin folder. Import the plugin or merge the example into your local hooks configuration, then review and trust it in ChatGPT/Codex. No separate OpenAI API key is needed. Works with local Work/Codex sessions on this Mac; ordinary web chats do not publish these events.").foregroundStyle(.secondary)
                HStack { Link("Hook setup guide",destination:URL(string:"https://learn.chatgpt.com/docs/hooks")!); Link("Open ChatGPT",destination:URL(string:"https://chatgpt.com/")!) }
            }
            Section("Forwarded inbox") { Text("The Inbox module shows notifications explicitly forwarded through this local bridge. Only alerts you forward using the bridge appear here.").foregroundStyle(.secondary) }
            if let error = bridge.error { Section { Text(error).foregroundStyle(.orange) } }
        }.formStyle(.grouped)
    }
}
struct IslandAgentView:View {
    @EnvironmentObject var vm:IslandViewModel
    @ObservedObject var bridge = IslandAgentBridge.shared
    @State var selected:IslandAgentBridge.Event?
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            IslandChatGPTDraft()
            Divider().padding(.vertical,4)
            IslandModuleHeading(title:"Agent activity",subtitle:"Local hooks · explicit approvals")
            if bridge.folderName == nil { Text("Connect a private bridge folder under Settings → Agents & Inbox.").foregroundStyle(.secondary) }
            if bridge.events.isEmpty { Text("No sessions have reported yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(bridge.sessions.prefix(30)) { event in
                Button { vm.isBatteryPopoverActive = true; selected = event } label: { HStack { Image(systemName:event.pending ? "hand.raised.fill" : "terminal").foregroundStyle(event.pending ? .orange : .secondary); Text(event.providerName+" · "+event.title).lineLimit(1); Spacer(); Text(event.resolution ?? (event.pending ? "Needs approval" : event.event)).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            }
        }.sheet(item:$selected,onDismiss:{ vm.isBatteryPopoverActive = false }) { event in IslandAgentRequestView(event:event,bridge:bridge).padding(24).frame(width:560,height:410) }
        .onDisappear { vm.isBatteryPopoverActive = false }
    }
}
struct IslandAgentRequestView:View {
    let event:IslandAgentBridge.Event
    @ObservedObject var bridge:IslandAgentBridge
    @Environment(\.dismiss) var dismiss
    @State var confirm = false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(event.providerName+" · "+event.title).font(.headline);Spacer();if ["chatgpt","codex"].contains(event.provider),let url=IslandChatGPTLinks.session(event.session) { Link("Open chat",destination:url) } }
            Text("Review the complete request. Allow applies once and never creates an always-allow rule.").foregroundStyle(.secondary)
            ScrollView { Text(event.request).font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            if !event.message.isEmpty { Text(event.message).font(.caption).lineLimit(3) }
            TimelineView(.periodic(from:.now,by:1)) { _ in
                HStack { Button("Close") { dismiss() }; Spacer(); Button("Deny",role:.destructive) { bridge.decide(event,allow:false); dismiss() }.disabled(!event.pending); Button("Allow once") { confirm = true }.buttonStyle(.borderedProminent).disabled(!event.pending) }
            }
        }.confirmationDialog("Allow this one request?",isPresented:$confirm) { Button("Allow once") { bridge.decide(event,allow:true); dismiss() }; Button("Cancel",role:.cancel) {} }
    }
}
struct IslandInboxView:View {
    @ObservedObject var bridge = IslandAgentBridge.shared
    @ObservedObject var notices=IslandNotices.shared
    @AppStorage("island.inbox.seen") var seen = ""
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { Text("Inbox").font(.headline); Spacer(); Button("Mark all read") { seen = bridge.notices.map(\.id).joined(separator:",");notices.markRead() } }
            Text("Alerts explicitly forwarded to Island · local only").font(.caption).foregroundStyle(.secondary)
            ForEach(notices.items) { item in HStack(alignment:.top) { if !item.read { Circle().fill(.blue).frame(width:5,height:5).padding(.top,5) };VStack(alignment:.leading,spacing:3) { Text(item.title).fontWeight(.medium);Text(item.body).font(.caption).foregroundStyle(.secondary) };Spacer();Text(item.source).font(.caption2).foregroundStyle(.secondary) }.padding(.vertical,5) }
            if bridge.notices.isEmpty && notices.items.isEmpty { Text("No forwarded alerts. Configure the local bridge under Settings → Agents & Inbox.").foregroundStyle(.secondary) }
            ForEach(bridge.notices.prefix(50)) { event in
                VStack(alignment:.leading,spacing:3) { HStack { if !seen.contains(event.id) { Circle().fill(.blue).frame(width:5,height:5) }; Text(event.title).fontWeight(.medium); Spacer(); Text(Date(timeIntervalSince1970:event.time),style:.time).font(.caption).foregroundStyle(.secondary) }; Text(event.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.vertical,5)
            }
        }
    }
}
