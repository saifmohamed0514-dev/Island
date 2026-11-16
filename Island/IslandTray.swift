import SwiftUI
import AppKit

@MainActor final class IslandAirDropSession:NSObject,ObservableObject,NSSharingServiceDelegate {
    @Published var active = false
    private var service:NSSharingService?
    private var urls:[URL] = []
    func share(_ values:[URL]) -> Bool {
        guard !values.isEmpty, let service = NSSharingService(named:.sendViaAirDrop) else { return false }
        urls = values.filter { !$0.isFileURL || $0.startAccessingSecurityScopedResource() }
        guard !urls.isEmpty else { return false }
        self.service = service; service.delegate = self; active = true; service.perform(withItems:urls); return true
    }
    private func finish() { urls.filter(\.isFileURL).forEach { $0.stopAccessingSecurityScopedResource() }; urls = []; service = nil; active = false }
    nonisolated func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]) { Task { @MainActor in self.finish() } }
    nonisolated func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error) { Task { @MainActor in self.finish() } }
}
struct IslandTrayView:View {
    @EnvironmentObject var vm:IslandViewModel
    @StateObject var tray = ShelfStateViewModel.shared
    @StateObject var preview = QuickLookService()
    @StateObject var airDrop = IslandAirDropSession()
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("File Tray").font(.system(size:14,weight:.semibold)); Text("\(tray.items.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add files…") { add() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { vm.isBatteryPopoverActive = airDrop.share(tray.items.compactMap(\.URL)) } label: { Label("AirDrop",systemImage:"airplayaudio") }.buttonStyle(.bordered).disabled(tray.isEmpty || airDrop.active)
            }
            Group {
                if tray.isEmpty {
                    HStack(spacing:14) { Image(systemName:"tray.and.arrow.down").font(.system(size:26,weight:.light)).foregroundStyle(.cyan); VStack(alignment:.leading,spacing:4) { Text("Keep it close.").font(.system(size:17,weight:.medium)); Text("Drop files, links or text. Drag them out when you’re ready.").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:20))
                } else {
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:10) { ForEach(tray.items) { item in IslandTrayTile(item:item,preview:preview).environmentObject(vm) } } }
                }
            }.overlay { RoundedRectangle(cornerRadius:20).stroke(vm.dragDetectorTargeting ? .cyan.opacity(0.7) : .white.opacity(0.08),lineWidth:1) }
            .onDrop(of:[.fileURL,.url,.utf8PlainText,.plainText],isTargeted:$vm.dragDetectorTargeting) { providers in vm.dropEvent = true; tray.load(providers);IslandHaptics.play(.placement); return true }
        }.frame(height:134).padding(.horizontal,12).quickLookPresenter(using:preview)
        .onChange(of:airDrop.active) { vm.isBatteryPopoverActive = airDrop.active || preview.isQuickLookOpen }
        .onChange(of:preview.isQuickLookOpen) { vm.isBatteryPopoverActive = airDrop.active || preview.isQuickLookOpen }
        .onDisappear { if !airDrop.active { vm.isBatteryPopoverActive = false }; preview.hide() }
    }
    func add() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        tray.load(panel.urls.map { NSItemProvider(object:$0 as NSURL) });IslandHaptics.play(.placement)
    }
}
struct IslandTrayTile:View {
    let item:ShelfItem
    let preview:QuickLookService
    @EnvironmentObject var vm:IslandViewModel
    @StateObject private var model:ShelfItemViewModel
    @State private var dragPreviewImage:NSImage?
    init(item:ShelfItem,preview:QuickLookService) { self.item = item; self.preview = preview; _model = StateObject(wrappedValue:ShelfItemViewModel(item:item)) }
    var body:some View {
        Button(action:open) { tileContent }.buttonStyle(.plain)
        .overlay {
            DraggableClickHandler(item:item,viewModel:model,cachedPreviewImage:$dragPreviewImage,dragPreviewContent:{ tileContent },onRightClick:showContextMenu,onClick:{ _,_ in ShelfSelectionModel.shared.selectSingle(item) },onActivate:open)
                .accessibilityHidden(true)
        }
        .onAppear { cacheDragPreview() }
        .onChange(of:model.thumbnail) { _,_ in cacheDragPreview() }
        .contextMenu {
            Button("Open",action:open)
            if let url = item.URL { Button("Quick Look") { quickLook(url) } }
            Button("Show in Finder") { ShelfActionService.reveal(item) }
            if let url=item.URL,url.isFileURL { Button("File actions…") { fileActions(url) } }
            Divider(); Button("Remove from tray",role:.destructive) { trayRemove() }
        }
    }
    private var tileContent:some View {
        VStack(spacing:7) {
            Image(nsImage:model.thumbnail ?? item.icon).resizable().scaledToFit().frame(width:40,height:40)
            Text(item.displayName.isEmpty ? "Item" : item.displayName).font(.system(size:10,weight:.medium)).lineLimit(1).truncationMode(.middle)
        }.padding(10).frame(width:90,height:84).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:16))
    }
    private func open() { IslandHaptics.play(.selection);ShelfActionService.open(item) }
    private func cacheDragPreview() {
        let renderer=ImageRenderer(content:tileContent)
        renderer.scale=NSScreen.main?.backingScaleFactor ?? 2
        dragPreviewImage=renderer.nsImage ?? item.icon
    }
    private func quickLook(_ url:URL) { vm.isBatteryPopoverActive=true;preview.show(urls:[url]) }
    private func fileActions(_ url:URL) { IslandFileSelection.shared.set([url]);IslandModuleStore.shared.setEnabled(.files,true);IslandCoordinator.shared.currentView = .files }
    private func showContextMenu(_ event:NSEvent,_ view:NSView) {
        let menu=NSMenu()
        func add(_ title:String,_ action:@escaping()->Void) {
            let target=IslandTrayMenuAction(action),entry=NSMenuItem(title:title,action:#selector(IslandTrayMenuAction.invokeTrayAction),keyEquivalent:"")
            entry.target=target;entry.representedObject=target;menu.addItem(entry)
        }
        add("Open",open)
        if let url=item.URL { add("Quick Look") { quickLook(url) } }
        add("Show in Finder") { ShelfActionService.reveal(item) }
        if let url=item.URL,url.isFileURL { add("File actions…") { fileActions(url) } }
        menu.addItem(.separator());add("Remove from tray",trayRemove)
        NSMenu.popUpContextMenu(menu,with:event,for:view)
    }
    func trayRemove() { IslandHaptics.play(.selection);ShelfActionService.remove(item) }
}
@MainActor private final class IslandTrayMenuAction:NSObject {
    let action:()->Void
    init(_ action:@escaping()->Void) { self.action=action }
    @objc func invokeTrayAction() { action() }
}
