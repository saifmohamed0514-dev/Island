import AppKit

// Capture only exported entries. A cancelled, rejected or internal drop must
// never remove items, and a late completion cannot consume the next drag.
struct IslandTrayDragCompletion {
    var itemIDs=Set<UUID>()
    var context:NSDraggingContext?
    mutating func finish(operation:NSDragOperation,removeEnabled:Bool)->Set<UUID> {
        defer { itemIDs=[];context=nil }
        guard removeEnabled,context == .outsideApplication,!operation.isEmpty else { return [] }
        return itemIDs
    }
}
