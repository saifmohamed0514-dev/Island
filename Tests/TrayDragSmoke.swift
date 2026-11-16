import AppKit

@main struct TrayDragSmoke {
    @MainActor static func main() throws {
        var count=0
        func check(_ value:Bool) { precondition(value,"Tray drag check \(count+1)");count+=1 }
        let first=UUID(),second=UUID()
        var drag=IslandTrayDragCompletion(itemIDs:[first,second],context:.outsideApplication)
        check(drag.finish(operation:[],removeEnabled:true).isEmpty)
        check(drag.itemIDs.isEmpty && drag.context == nil)
        for operation:NSDragOperation in [.copy,.move,.link,.generic] {
            drag=IslandTrayDragCompletion(itemIDs:[first,second],context:.outsideApplication)
            check(drag.finish(operation:operation,removeEnabled:true)==[first,second])
            check(drag.finish(operation:operation,removeEnabled:true).isEmpty)
        }
        drag=IslandTrayDragCompletion(itemIDs:[first],context:.outsideApplication)
        check(drag.finish(operation:.copy,removeEnabled:false).isEmpty)
        check(drag.itemIDs.isEmpty && drag.context == nil)
        drag=IslandTrayDragCompletion(itemIDs:[first],context:.withinApplication)
        check(drag.finish(operation:.copy,removeEnabled:true).isEmpty)
        drag=IslandTrayDragCompletion(itemIDs:[first])
        check(drag.finish(operation:.copy,removeEnabled:true).isEmpty)
        drag=IslandTrayDragCompletion(context:.outsideApplication)
        check(drag.finish(operation:.copy,removeEnabled:true).isEmpty)

        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let original=folder.appendingPathComponent("Original.txt"),temporary=folder.appendingPathComponent("Export.txt")
        try Data("Original".utf8).write(to:original);try Data("Keep for receiver".utf8).write(to:temporary)
        let replacement=UUID()
        let store=ShelfStateViewModel(items:[.init(id:first,url:original),.init(id:second,url:temporary),.init(id:replacement,url:original)])
        store.removeAfterDrag([]);check(store.items.count==3)
        store.removeAfterDrag([first,second]);check(store.items.map(\.id)==[replacement])
        check(try Data(contentsOf:original)==Data("Original".utf8))
        check(try Data(contentsOf:temporary)==Data("Keep for receiver".utf8))
        check(ShelfItem.cleanupCount==0)
        store.removeAfterDrag([first,UUID()]);check(store.items.map(\.id)==[replacement])
        print("PASS: \(count) production tray-drag checks; rejected/cancelled/internal drops, setting off, one-shot completion, captured IDs, same-file replacement and original/temporary file preservation")
    }
}
