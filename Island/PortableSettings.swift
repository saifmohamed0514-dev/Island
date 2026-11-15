import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

struct IslandPortableSettings:Codable,Equatable {
    var format=1
    var appearance=IslandAppearancePreferences()
    var layout:IslandDesignerSnapshot
    var flags:[String:Bool]=[:]
    var numbers:[String:Double]=[:]
    var choices:[String:String]=[:]
    static let booleanKeys:Set<String>=["island.gesture.middleCycle","island.gesture.skip","island.gesture.dismiss","island.gesture.natural","island.gesture.downCycle","island.gesture.optionActions","island.live.musicQuickControls","island.live.aiPriority","island.hud.labels","island.hud.relativeDB","island.hud.elastic","enableHaptics","openNotchOnHover","enableGestures","enableGradient","systemEventIndicatorUseAccent","systemEventIndicatorShadow","showClosedNotchHUDPercentage","showOpenNotchHUDPercentage"]
    static let ranges:[String:ClosedRange<Double>]=["minimumHoverDuration":0.05...1,"gestureSensitivity":5...100,"island.hud.duration":0.6...8]
    static let enums:[String:Set<String>]=["island.hud.motion":["smooth","fast","instant"]]
    mutating func normalize() throws {
        guard format==1,flags.count<=64,numbers.count<=16,choices.count<=16 else { throw CocoaError(.fileReadCorruptFile) }
        appearance.normalize();layout.normalize()
        flags=flags.filter { Self.booleanKeys.contains($0.key) }
        numbers=numbers.compactMapValues { $0.isFinite ? $0 : nil }.filter { Self.ranges[$0.key] != nil }
        for (key,value) in numbers { if let range=Self.ranges[key] { numbers[key]=min(range.upperBound,max(range.lowerBound,value)) } }
        choices=choices.filter { Self.enums[$0.key]?.contains($0.value)==true }
    }
    static func decode(_ data:Data) throws ->Self {
        guard data.count<=262144 else { throw CocoaError(.fileReadTooLarge) }
        var value=try JSONDecoder().decode(Self.self,from:data);try value.normalize();return value
    }
    func encoded() throws ->Data { let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(self) }
}
@MainActor extension IslandPortableSettings {
    static func current(includeHUD:Bool=true,defaults:UserDefaults = .standard)->Self {
        var value=Self(appearance:IslandAppearanceStore.shared.preferences,layout:.current())
        for key in booleanKeys where includeHUD || !isHUD(key) { if let raw=defaults.object(forKey:key) as? Bool { value.flags[key]=raw } }
        for key in ranges.keys where includeHUD || !isHUD(key) { if let raw=defaults.object(forKey:key) as? Double { value.numbers[key]=raw } }
        for key in enums.keys where includeHUD || !isHUD(key) { if let raw=defaults.string(forKey:key) { value.choices[key]=raw } }
        // App-use recording is a per-Mac choice, never enabled by a shared layout.
        value.layout.modules.enabled.removeAll { $0 == .usage };value.layout.modules.normalize()
        try? value.normalize();return value
    }
    static func isHUD(_ key:String)->Bool { key.hasPrefix("island.hud.") || ["enableGradient","systemEventIndicatorUseAccent","systemEventIndicatorShadow","showClosedNotchHUDPercentage","showOpenNotchHUDPercentage"].contains(key) }
    func apply(includeHUD:Bool=true,defaults:UserDefaults = .standard) {
        var value=self;guard (try? value.normalize()) != nil else { return }
        IslandAppearanceStore.shared.restore(value.appearance)
        var layout=value.layout
        if !IslandModuleStore.shared.enabled.contains(.usage) { layout.modules.enabled.removeAll { $0 == .usage } }
        else if !layout.modules.enabled.contains(.usage) { layout.modules.enabled.append(.usage) }
        layout.normalize();layout.apply()
        for (key,value) in value.flags where includeHUD || !Self.isHUD(key) { defaults.set(value,forKey:key) }
        for (key,value) in value.numbers where includeHUD || !Self.isHUD(key) { defaults.set(value,forKey:key) }
        for (key,value) in value.choices where includeHUD || !Self.isHUD(key) { defaults.set(value,forKey:key) }
        NotificationCenter.default.post(name:Notification.Name("IslandActivityTraysChanged"),object:nil)
    }
}
@MainActor final class IslandSettingsSharing:ObservableObject {
    static let shared=IslandSettingsSharing()
    @Published private(set) var folderName:String?
    @Published private(set) var pending:IslandPortableSettings?
    @Published private(set) var message="Choose a folder on iCloud Drive, or another folder you sync."
    @Published private(set) var importSource=""
    var includeHUD:Bool { UserDefaults.standard.bool(forKey:"island.settings.syncHUD") }
    private var folder:URL?,scope=false,lastData:Data?,pendingData:Data?
    private var task:Task<Void,Never>?
    private var lastLocalData:Data?
    private let fileName="Island Settings.json"
    init() {
        guard let data=UserDefaults.standard.data(forKey:"island.settings.syncFolder") else { return }
        do { var stale=false;let url=try URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale);guard !stale else { message="Choose your sync folder again to restore access.";return };connect(url) }
        catch { message="Choose your sync folder again to restore access." }
    }
    func chooseFolder() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false;panel.prompt="Use Folder";panel.message="Choose a folder on iCloud Drive to sync Island’s appearance and layouts between your Macs."
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { let data=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil);disconnect();UserDefaults.standard.set(data,forKey:"island.settings.syncFolder");connect(url) }
        catch { message="Couldn’t keep access to that folder. Choose another folder." }
    }
    private func connect(_ url:URL) {
        folder=url;scope=url.startAccessingSecurityScopedResource();folderName=url.lastPathComponent
        lastLocalData=try? IslandPortableSettings.current(includeHUD:includeHUD).encoded()
        task?.cancel();task=Task { @MainActor [weak self] in
            while !Task.isCancelled { self?.check();self?.shareLocalChanges();do { try await Task.sleep(for:.seconds(15)) } catch { return } }
        }
    }
    func disconnect() {
        task?.cancel();task=nil;if scope { folder?.stopAccessingSecurityScopedResource() };scope=false;folder=nil;folderName=nil;pending=nil;lastData=nil
        UserDefaults.standard.removeObject(forKey:"island.settings.syncFolder");message="Settings sync is off. The shared file is kept."
    }
    func check() {
        guard let folder else { return }
        let url=folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath:url.path) else { message="Folder connected. Use ‘Share this Mac’s settings’ to start.";return }
        do {
            let data=try read(url);guard data != lastData else { return }
            let value=try IslandPortableSettings.decode(data)
            if value == IslandPortableSettings.current(includeHUD:includeHUD) { lastData=data;return }
            pending=value;pendingData=data;importSource="Sync folder";message="Shared settings are ready to review. Nothing changes until you apply them."
        } catch { message="The shared settings file couldn’t be read. Your current settings are kept." }
    }
    private func shareLocalChanges() {
        guard UserDefaults.standard.bool(forKey:"island.settings.autoShare"),pending==nil,let data=try? IslandPortableSettings.current(includeHUD:includeHUD).encoded(),data != lastLocalData else { return }
        publish()
    }
    func publish() {
        guard let folder,pending==nil else { message="Apply or dismiss the incoming settings before sharing this Mac’s version.";return }
        do {
            // Recheck before replacing to avoid overwriting another Mac’s unseen edit.
            let url=folder.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath:url.path) {
                let latest=try read(url)
                _ = try IslandPortableSettings.decode(latest)
                if latest != lastData { check();if pending != nil { return } }
            }
            let data=try IslandPortableSettings.current(includeHUD:includeHUD).encoded();try data.write(to:url,options:.atomic);lastData=data;lastLocalData=data;message="Shared. Other connected Macs can review these settings."
        } catch { message="Couldn’t write the shared file. Check the folder and try again." }
    }
    func export() {
        let panel=NSSavePanel();panel.nameFieldStringValue=fileName;panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let scope=url.startAccessingSecurityScopedResource();defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do { try IslandPortableSettings.current(includeHUD:true).encoded().write(to:url,options:.atomic);message="Settings exported. Personal content and access grants were excluded." } catch { message="Couldn’t export settings." }
    }
    func importFile() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let scope=url.startAccessingSecurityScopedResource();defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do { pending=try IslandPortableSettings.decode(read(url));pendingData=nil;importSource=url.lastPathComponent;message="Review the imported appearance and layout before applying." } catch { message="This isn’t a supported Island settings file. Your settings are kept." }
    }
    func apply() {
        guard let pending else { return }
        if let pendingData,let folder,(try? read(folder.appendingPathComponent(fileName))) != pendingData { check();message="Shared settings changed again. Review the latest version before applying.";return }
        pending.apply(includeHUD:pendingData==nil || includeHUD)
        self.pending=nil;lastLocalData=try? IslandPortableSettings.current(includeHUD:includeHUD).encoded()
        if let pendingData { lastData=pendingData };pendingData=nil
        message="Appearance and layout applied. Recording, permissions, connections and private content were kept."
    }
    func dismiss() { pending=nil;if let folder { lastData=try? read(folder.appendingPathComponent(fileName)) };message="Incoming settings dismissed. This Mac’s settings are kept." }
    private func read(_ url:URL)throws->Data {
        let info=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile==true,info.isSymbolicLink != true,(info.fileSize ?? Int.max)<=262144 else { throw CocoaError(.fileReadCorruptFile) }
        return try Data(contentsOf:url,options:.uncached)
    }
}
struct IslandSettingsSharingView:View {
    @ObservedObject private var sharing=IslandSettingsSharing.shared
    @AppStorage("island.settings.syncHUD") private var includeHUD=false
    @AppStorage("island.settings.autoShare") private var autoShare=false
    var body:some View {
        Form {
            Section("Take your Island with you") {
                Text("Export a backup, or use a folder on iCloud Drive to share appearance, module layouts, trays and gestures between your Macs. Changes are reviewed before applying.").foregroundStyle(.secondary)
                HStack { Button("Export Settings…") { sharing.export() };Button("Import Settings…") { sharing.importFile() } }
                Text("Passwords, connections, file access, notes, events, audio capture, Screen Time, login and update choices stay on each Mac.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Shared folder") {
                if let folder=sharing.folderName { LabeledContent("Folder",value:folder);Toggle("Include HUD appearance",isOn:$includeHUD);Toggle("Share changes automatically",isOn:$autoShare).onChange(of:autoShare) { if autoShare { sharing.publish() } };HStack { Button("Share this Mac’s settings") { sharing.publish() }.disabled(sharing.pending != nil);Button("Check now") { sharing.check() };Button("Disconnect") { sharing.disconnect() } } }
                else { Button("Choose Sync Folder…") { sharing.chooseFolder() } }
                Text(sharing.message).font(.caption).foregroundStyle(.secondary)
                Text("iCloud Drive must be enabled on both Macs. Island uses only the folder you choose; it doesn’t sign you into iCloud or create a CloudKit account.").font(.caption).foregroundStyle(.secondary)
            }
            if let incoming=sharing.pending {
                Section("Review · "+sharing.importSource) {
                    LabeledContent("Enabled modules",value:"\(incoming.layout.modules.enabled.filter { $0 != .usage }.count)")
                    LabeledContent("Activity trays",value:"\(incoming.layout.activities?.enabled.count ?? 0)")
                    LabeledContent("Appearance",value:incoming.appearance.notchlessStyle.capitalized+" · "+incoming.appearance.outline+" outline")
                    Text("Applying replaces the included appearance and layout choices. Your private content and system access are kept.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Apply Settings") { sharing.apply() }.buttonStyle(.borderedProminent);Button("Keep This Mac’s Settings") { sharing.dismiss() } }
                }
            }
        }.formStyle(.grouped)
    }
}
