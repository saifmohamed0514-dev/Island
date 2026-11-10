import Foundation
import UniformTypeIdentifiers
@main struct DesignerSmoke {
    @MainActor static func main() async throws {
        var count=0
        func check(_ value:Bool) { precondition(value,"Designer check \(count+1)");count+=1 }
        var original=IslandModulePreferences();original.normalize()
        var prefs=original
        prefs.place(.notes,relativeTo:.home)
        check(prefs.enabled == [.dashboard,.notes,.home,.shelf,.focus])
        prefs=original;prefs.place(.dashboard,relativeTo:.focus,after:true)
        check(prefs.enabled == [.home,.shelf,.focus,.dashboard,.notes])
        prefs=original;prefs.place(.weather,relativeTo:.home)
        check(prefs.enabled == [.dashboard,.weather,.home,.shelf,.focus,.notes])
        check(prefs.start == original.start)
        let previousHidden=original.order.filter { !original.enabled.contains($0) && $0 != .weather }
        check(prefs.order.filter { !prefs.enabled.contains($0) } == previousHidden)
        prefs=original;prefs.place(.weather)
        check(prefs.enabled.last == .weather && prefs.enabled.count == 6)
        let appended=prefs;prefs.place(.weather)
        check(prefs == appended)
        prefs.place(.weather,relativeTo:.weather)
        check(prefs == appended)
        prefs.place(.weather,relativeTo:.dashboard)
        check(prefs.enabled.first == .weather && Array(prefs.enabled.prefix(5)) == [.weather,.dashboard,.home,.shelf,.focus])
        check(Set(prefs.enabled).count == prefs.enabled.count)
        check(Set(prefs.order) == Set(NotchViews.allCases) && prefs.order.count == NotchViews.allCases.count)
        let restored=try JSONDecoder().decode(IslandModulePreferences.self,from:JSONEncoder().encode(prefs))
        check(restored == prefs)
        prefs=original;prefs.place(.focus,relativeTo:.inbox)
        check(prefs.enabled.last == .focus)
        let undo=original;prefs.place(.translation);prefs=undo
        check(prefs == original)
        let transfer=IslandModuleTransfer(module:.weather)
        check(try JSONDecoder().decode(IslandModuleTransfer.self,from:JSONEncoder().encode(transfer)).module == .weather)
        check((try? JSONDecoder().decode(IslandModuleTransfer.self,from:Data("{\"module\":\"not-a-module\"}".utf8))) == nil)
        check((try? JSONDecoder().decode(IslandModuleTransfer.self,from:Data("{\"module\":42}".utf8))) == nil)
        check(UTType.islandModule.identifier == "org.islandapp.module" && UTType.islandModule != .plainText)
        var corrupt=original;corrupt.order=[.focus,.focus];corrupt.enabled=[.focus,.focus];corrupt.start = .focus
        corrupt.place(.notes,relativeTo:.focus)
        check(corrupt.enabled == [.notes,.focus] && corrupt.start == .focus && corrupt.order.count == NotchViews.allCases.count)
        try CanvasSmoke.run()
        try SavedLayoutsSmoke.run()
        print("PASS: \(count) production module-placement and typed-drag checks; before/after, hidden modules, overflow, default preservation, duplicates, persistence and invalid payloads; no live settings changed")
    }
}
