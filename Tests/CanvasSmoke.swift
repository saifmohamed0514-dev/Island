import Foundation
@MainActor final class IslandModuleStore {
    static let shared=IslandModuleStore()
    var enabled:[NotchViews]=[.dashboard,.home,.shelf,.focus]
    var lastRequest:[NotchViews]=[]
    func enableForCanvas(_ values:[NotchViews]) { lastRequest=values;enabled=Array(Set(enabled+values+[.dashboard])) }
}
@MainActor final class IslandCoordinator {
    static let shared=IslandCoordinator()
    var currentView:NotchViews = .notes
    var showingCanvasDetail=true
}
struct CanvasSmoke {
    @MainActor static func run() throws {
        var count=0
        func check(_ value:Bool) { precondition(value,"Canvas check \(count+1)");count+=1 }
        var prefs=IslandCanvasPreferences();prefs.slots=[.home,.focus,nil,nil]
        check(prefs.place(.weather,at:3) && prefs.slots == [.home,.focus,nil,.weather] && prefs.enabled)
        prefs.place(.home,at:1);check(prefs.slots == [.focus,.home,nil,.weather])
        prefs.place(.focus,at:2);check(prefs.slots == [nil,.home,.focus,.weather])
        prefs.place(.notes,at:1);check(prefs.slots == [nil,.notes,.focus,.weather] && !prefs.modules.contains(.home))
        let before=prefs;prefs.place(.notes,at:1);check(prefs == before)
        check(!prefs.place(.notes,at:-1) && prefs == before)
        check(!prefs.place(.notes,at:4) && prefs == before)
        check(prefs.remove(.focus) && prefs.slots == [nil,.notes,nil,.weather])
        check(!prefs.remove(.focus))
        prefs.remove(.notes);prefs.remove(.weather);check(prefs.modules.isEmpty && prefs.slots.count == 4)
        prefs.slots=[.home,.home,.notes,.weather,.focus];prefs.normalize();check(prefs.slots == [.home,nil,.notes,.weather])
        prefs.slots=[.focus];prefs.normalize();check(prefs.slots == [.focus,nil,nil,nil])
        let initial=IslandCanvasPreferences.initial(modules:[.dashboard,.notes,.home,.weather,.focus])
        check(initial.slots == [.notes,.home,.weather,nil] && !initial.enabled)
        check(IslandCanvasPreferences.initial(modules:[]).slots == [.dashboard,nil,nil,nil])
        check(try JSONDecoder().decode(IslandCanvasPreferences.self,from:JSONEncoder().encode(initial)) == initial)
        check((try? JSONDecoder().decode(IslandCanvasPreferences.self,from:Data("{\"enabled\":true,\"slots\":[\"unknown\"]}".utf8))) == nil)
        var navigation=initial
        check(!navigation.showsLayout(currentView:.dashboard,showingDetail:false))
        navigation.enabled=true
        check(navigation.showsLayout(currentView:.dashboard,showingDetail:false))
        check(!navigation.showsLayout(currentView:.dashboard,showingDetail:true))
        check(!navigation.showsLayout(currentView:.focus,showingDetail:false))
        let domain="IslandCanvasTests-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:domain)!
        // Only this test's private suite receives writes; no live app preferences.
        defer { defaults.removePersistentDomain(forName:domain) }
        let store=IslandCanvasStore(defaults:defaults)
        check(!store.preferences.enabled)
        store.place(.weather,at:3)
        check(store.preferences.enabled && store.preferences.slots[3] == .weather && IslandModuleStore.shared.lastRequest == [.weather])
        check(IslandCoordinator.shared.currentView == .dashboard && !IslandCoordinator.shared.showingCanvasDetail)
        let restored=IslandCanvasStore(defaults:defaults);check(restored.preferences == store.preferences)
        IslandModuleStore.shared.enabled.removeAll { $0 == .weather }
        restored.place(.weather,at:1);check(IslandModuleStore.shared.lastRequest.isEmpty && !IslandModuleStore.shared.enabled.contains(.weather))
        IslandModuleStore.shared.enabled.append(.weather)
        restored.remove(.weather);check(!restored.preferences.modules.contains(.weather) && IslandModuleStore.shared.enabled.contains(.weather))
        restored.setEnabled(false);check(!IslandCanvasStore(defaults:defaults).preferences.enabled)
        restored.template("Work");check(restored.preferences.slots == [.calendar,.tasks,.focus,.notes] && restored.preferences.enabled)
        let snapshot=restored.preferences;restored.template("Simple");check(restored.preferences.slots == [.home,.focus,nil,nil])
        restored.restore(snapshot);check(IslandCanvasStore(defaults:defaults).preferences == snapshot)
        defaults.set(Data("broken".utf8),forKey:"island.canvas.layout");check(!IslandCanvasStore(defaults:defaults).preferences.enabled)
        print("PASS: \(count) production canvas checks; slot swaps/replacement, empty positions, migration, real store persistence, activation, removal and disabled-module preservation; private test defaults only")
    }
}
