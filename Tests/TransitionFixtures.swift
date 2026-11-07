// Isolated dependencies for the actual open/close methods; no desktop interaction.
import Foundation
import Combine
enum NotchState { case open,closed }
enum Module { case home,dashboard,focus,notes,shelf }
let openNotchSize=CGSize(width:680,height:216)
func getClosedNotchSize(screenUUID:String?=nil)->CGSize { CGSize(width:185,height:32) }
@MainActor final class IslandCoordinator {
    static let shared=IslandCoordinator()
    var currentView:Module = .focus
    var openLastTabByDefault=false
    var showingCanvasDetail=false
    struct Peek { var show=false }
    var sneakPeek=Peek()
}
@MainActor final class IslandModuleStore {
    static let shared=IslandModuleStore()
    var enabled:Set<Module> = [.dashboard,.focus,.notes,.shelf]
    var defaultModule:Module = .dashboard
}
@MainActor final class ShelfStateViewModel {
    static let shared=ShelfStateViewModel()
    var isEmpty=true
}
@MainActor enum Defaults {
    enum Key { case openShelfByDefault }
    static var shelfByDefault=false
    static subscript(key:Key)->Bool { shelfByDefault }
}
@MainActor final class MusicManager {
    static let shared=MusicManager()
    var updates=0
    func forceUpdate() { updates+=1 }
}
@MainActor final class SharingStateManager {
    static let shared=SharingStateManager()
    var preventNotchClose=false
}
@MainActor final class TestApplication { var modalWindow:Int? }
@MainActor let NSApp=TestApplication()
