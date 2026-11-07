import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// File commands use fixed executables and argument arrays, never a shell.
enum IslandFileCommands {
    static func run(_ executable:String,_ arguments:[String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func safeArchiveEntry(_ path:String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator:"/",omittingEmptySubsequences:false).contains("..") && !path.contains(":")
    }
    static func unzip(_ source:URL,to directory:URL) throws {
        let privateFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:privateFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:privateFolder) }
        let copy = privateFolder.appendingPathComponent("archive.zip"); try FileManager.default.copyItem(at:source,to:copy)
        let entries = try run("/usr/bin/zipinfo",["-1",copy.path]).split(separator:"\n").map(String.init)
        guard !entries.isEmpty, entries.count <= 10000, entries.allSatisfy(safeArchiveEntry) else { throw CocoaError(.fileReadCorruptFile) }
        let listing = try run("/usr/bin/zipinfo",["-l",copy.path])
        guard listing.range(of:#"(?m)^l[rwxstST-]{9}\s"#,options:.regularExpression) == nil else { throw CocoaError(.fileReadCorruptFile) }
        let total = try run("/usr/bin/zipinfo",["-t",copy.path])
        let expression = try NSRegularExpression(pattern:#"([0-9]+) files?, ([0-9]+) bytes uncompressed"#)
        let range = NSRange(total.startIndex..<total.endIndex,in:total)
        guard let match = expression.firstMatch(in:total,range:range), let bytesRange = Range(match.range(at:2),in:total), let bytes = UInt64(total[bytesRange]), bytes <= 2_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        do { _ = try run("/usr/bin/ditto",["-x","-k",copy.path,directory.path]) }
        catch { try? FileManager.default.removeItem(at:directory); throw error }
    }
    static func convert(_ source:URL,to output:URL,jpeg:Bool) throws {
        guard let image = CGImageSourceCreateWithURL(source as CFURL,nil), let destination = CGImageDestinationCreateWithURL(output as CFURL,(jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString,1,nil) else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImageFromSource(destination,image,0,nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
@MainActor final class IslandFileSelection:ObservableObject {
    static let shared=IslandFileSelection()
    @Published var urls:[URL]=[]
    private var scopes:[URL]=[]
    func set(_ values:[URL]) { scopes.forEach { $0.stopAccessingSecurityScopedResource() };urls=values;scopes=values.filter { $0.startAccessingSecurityScopedResource() } }
    func load(_ providers:[NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in
                let url:URL?;if let data=item as? Data { url=URL(dataRepresentation:data,relativeTo:nil) } else { url=item as? URL }
                guard let url,url.isFileURL else { return };Task { @MainActor in self.set(self.urls+[url]) }
            }
        }
    }
}
struct IslandFileActionsView: View {
    @ObservedObject var selection=IslandFileSelection.shared
    var selected:[URL] { get { selection.urls } nonmutating set { selection.set(newValue) } }
    @State var status = "Choose files for a quick action. Your originals are kept unless you choose Move or Trash."
    @State var busy = false
    @State var confirmTrash = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("File Actions").font(.headline); Spacer(); Button("Choose files…") { choose() }.disabled(busy);Button("Eject disk…") { eject() }.disabled(busy) }
            if !selected.isEmpty {
                Text(selected.map(\.lastPathComponent).joined(separator:", ")).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                HStack {
                    Menu("Organize") { Button("Copy to folder / cloud…") { copyOrMove(move:false) }; Button("Move to folder…") { copyOrMove(move:true) }; Button("Move to Trash",role:.destructive) { confirmTrash = true } }
                    Menu("Archive") { Button("Create ZIP…") { zip() }; Button("Extract ZIP…") { unzip() }.disabled(selected.count != 1 || selected.first?.pathExtension.lowercased() != "zip") }
                    Menu("Convert image") { Button("PNG…") { convert(jpeg:false) }; Button("JPEG…") { convert(jpeg:true) } }.disabled(selected.count != 1)
                    Menu("Open / Share") { Button("Open with app…") { openWith() }; Button("AirDrop…") { NSSharingService(named:.sendViaAirDrop)?.perform(withItems:selected) }; Button("Open in Music") { openMusic() } }
                }.disabled(busy)
            }
            Text(busy ? "Working…" : status).font(.caption).foregroundStyle(.secondary)
        }.padding(8).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:16))
        .onDrop(of:[.fileURL],isTargeted:nil) { providers in selection.load(providers);return true }
        .confirmationDialog("Move \(selected.count) selected items to Trash?",isPresented:$confirmTrash) { Button("Move to Trash",role:.destructive) { recycle() } }
    }
    func eject() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.message="Choose the removable disk itself under Locations."
        guard panel.runModal() == .OK,let selected=panel.url else { return }
        do {
            let values=try selected.resourceValues(forKeys:[.volumeURLKey,.volumeIsEjectableKey,.volumeIsRemovableKey])
            guard let volume=values.volume,!volume.path.isEmpty,volume.path != "/",values.volumeIsEjectable == true || values.volumeIsRemovable == true else { status="Choose a removable or ejectable volume. Your startup disk can’t be ejected here.";return }
            try NSWorkspace.shared.unmountAndEjectDevice(at:volume);status="The disk was ejected."
        } catch { status="macOS couldn’t eject that disk. Close files using it and try again in Finder." }
    }
    func choose() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { selected = panel.urls; status = "Choose an action." } }
    func folder() -> URL? { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; return panel.runModal() == .OK ? panel.url : nil }
    func save(extension ext:String) -> URL? { let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension:ext) ?? .data]; panel.nameFieldStringValue = (selected.first?.deletingPathExtension().lastPathComponent ?? "Selection")+"."+ext; return panel.runModal() == .OK ? panel.url : nil }
    func perform(destination:URL, operation:@escaping @Sendable ([URL],URL) throws -> Void) {
        let urls = selected; guard !urls.isEmpty else { return }; busy = true
        let scopes = (urls+[destination]).filter { $0.startAccessingSecurityScopedResource() }
        Task {
            let success = await Task.detached(priority:.userInitiated) { () -> Bool in do { try operation(urls,destination); return true } catch { return false } }.value
            scopes.forEach { $0.stopAccessingSecurityScopedResource() }; busy = false
            status = success ? "Finished. Your output is ready in the selected location." : "Couldn’t finish this action. Check access, format, free space and existing file names. Some items may already have moved or copied; check the destination before retrying. Very large or unsafe archives should be handled in Finder."
        }
    }
    func copyOrMove(move:Bool) {
        guard let destination = folder() else { return }
        perform(destination:destination) { urls,folder in
            var names = Set<String>()
            for source in urls { guard names.insert(source.lastPathComponent).inserted, !FileManager.default.fileExists(atPath:folder.appendingPathComponent(source.lastPathComponent).path) else { throw CocoaError(.fileWriteFileExists) } }
            for source in urls { let output = folder.appendingPathComponent(source.lastPathComponent); if move { try FileManager.default.moveItem(at:source,to:output) } else { try FileManager.default.copyItem(at:source,to:output) } }
        }
    }
    func zip() {
        guard let destination = save(extension:"zip") else { return }
        perform(destination:destination) { urls,output in
            guard !urls.contains(where: { output.standardizedFileURL.path == $0.standardizedFileURL.path || output.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path+"/") }) else { throw CocoaError(.fileWriteInvalidFileName) }
            if urls.count == 1 { _ = try IslandFileCommands.run("/usr/bin/ditto",["-c","-k","--keepParent",urls[0].path,output.path]); return }
            guard urls.allSatisfy({ (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) != true }) else { throw CocoaError(.fileReadUnsupportedScheme) }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:temp) }
            for url in urls { try FileManager.default.copyItem(at:url,to:temp.appendingPathComponent(url.lastPathComponent)) }
            _ = try IslandFileCommands.run("/usr/bin/ditto",["-c","-k",temp.path,output.path])
        }
    }
    func unzip() { guard selected.count == 1, let folder = folder() else { return }; let output = folder.appendingPathComponent((selected[0].deletingPathExtension().lastPathComponent)+"-"+String(UUID().uuidString.prefix(6)),isDirectory:true); perform(destination:folder) { urls,_ in try IslandFileCommands.unzip(urls[0],to:output) } }
    func convert(jpeg:Bool) { guard selected.count == 1, let output = save(extension:jpeg ? "jpg" : "png") else { return }; perform(destination:output) { urls,destination in guard urls[0].standardizedFileURL != destination.standardizedFileURL else { throw CocoaError(.fileWriteInvalidFileName) }; try IslandFileCommands.convert(urls[0],to:destination,jpeg:jpeg) } }
    func recycle() {
        let urls = selected; let scopes = urls.filter { $0.startAccessingSecurityScopedResource() }
        NSWorkspace.shared.recycle(urls) { _,error in scopes.forEach { $0.stopAccessingSecurityScopedResource() }; Task { @MainActor in status = error == nil ? "Moved to Trash. You can restore items in Finder." : "Some items couldn’t be moved. Check Finder before trying again."; selected = [] } }
    }
    func openWith() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let app = panel.url else { return }
        let urls = selected; let scopes = (urls+[app]).filter { $0.startAccessingSecurityScopedResource() }
        NSWorkspace.shared.open(urls,withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()) { _,_ in scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
    }
    func openMusic() { guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Music") else { return }; NSWorkspace.shared.open(selected,withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()) }
}
