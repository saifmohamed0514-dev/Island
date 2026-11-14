import Foundation
struct SavedLayoutsSmoke {
    @MainActor static func run() throws {
        var count=0
        func check(_ value:Bool) { precondition(value,"Saved layout check \(count+1)");count+=1 }
        let suite="IslandSavedLayoutsTests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("keep-this-note",forKey:"island.notes.fixture")
        var modules=IslandModulePreferences();modules.enabled=[.home,.focus];modules.start = .home;modules.normalize()
        var snapshot=IslandDesignerSnapshot(modules:modules,canvas:IslandCanvasPreferences(enabled:true,slots:[.home,.focus,nil,nil]))
        let store=IslandSavedLayoutStore(defaults:defaults)
        check(store.layouts.isEmpty && store.lastDeleted == nil)
        check(store.save(name:"  Study  ",snapshot:snapshot) == nil)
        let saved=store.layouts[0]
        check(saved.name == "Study" && saved.snapshot == snapshot)
        check(IslandSavedLayoutStore(defaults:defaults).layouts == store.layouts)
        check(store.save(name:"study",snapshot:snapshot) != nil && store.layouts.count == 1)
        check(store.save(name:"STÚDY",snapshot:snapshot) != nil)
        check(store.save(name:"\n  ",snapshot:snapshot) != nil && store.save(name:String(repeating:"a",count:41),snapshot:snapshot) != nil)
        check(store.save(name:"A\nB",snapshot:snapshot) != nil)
        snapshot.canvas.slots=[.notes,.shelf,nil,nil]
        check(store.save(name:"Study",snapshot:snapshot,replacing:saved.id) == nil && store.layouts[0].id == saved.id && store.layouts[0].snapshot == snapshot)
        check(store.rename(saved.id,to:"Evening") == nil && store.layouts[0].name == "Evening")
        check(store.save(name:"Other",snapshot:snapshot) == nil)
        check(store.rename(saved.id,to:"Other") != nil && store.layouts[0].name == "Evening")
        let before=store.layouts
        check(store.save(name:"Missing",snapshot:snapshot,replacing:UUID()) != nil && store.layouts == before)
        store.delete(saved.id)
        check(store.layouts.count == 1 && store.lastDeleted?.name == "Evening")
        let reloaded=IslandSavedLayoutStore(defaults:defaults)
        check(reloaded.lastDeleted?.id == saved.id && reloaded.undoDelete() == nil)
        check(reloaded.layouts.contains { $0.id == saved.id } && reloaded.lastDeleted == nil)
        check(IslandSavedLayoutStore(defaults:defaults).lastDeleted == nil)
        reloaded.delete(saved.id);check(reloaded.save(name:"Evening",snapshot:snapshot) == nil)
        check(reloaded.undoDelete() != nil && reloaded.lastDeleted?.id == saved.id)
        let conflicting=reloaded.layouts.first { $0.name == "Evening" }!
        check(reloaded.rename(conflicting.id,to:"Different") == nil && reloaded.undoDelete() == nil)
        while reloaded.layouts.count<IslandSavedLayoutStore.limit { check(reloaded.save(name:"Layout \(reloaded.layouts.count)",snapshot:snapshot) == nil) }
        check(reloaded.save(name:"One too many",snapshot:snapshot) != nil && reloaded.layouts.count == 12)
        let id=reloaded.layouts[0].id
        check(reloaded.rename(id,to:"Renamed while full") == nil)
        reloaded.delete(id);check(reloaded.save(name:"New layout",snapshot:snapshot) == nil && reloaded.undoDelete() != nil)
        check(defaults.string(forKey:"island.notes.fixture") == "keep-this-note")
        defaults.set(Data("broken".utf8),forKey:"island.layouts.saved")
        check(IslandSavedLayoutStore(defaults:defaults).layouts.isEmpty)
        var malformed=snapshot;malformed.canvas.slots=[.home,.home];malformed.modules.enabled=[]
        let raw=[IslandSavedLayout(id:UUID(),name:"  Normalized ",snapshot:malformed),IslandSavedLayout(id:UUID(),name:"normalized",snapshot:snapshot)]
        defaults.set(try JSONEncoder().encode(raw),forKey:"island.layouts.saved")
        let normalized=IslandSavedLayoutStore(defaults:defaults)
        check(normalized.layouts.count == 1 && normalized.layouts[0].snapshot.canvas.slots == [.home,nil,nil,nil] && !normalized.layouts[0].snapshot.modules.enabled.isEmpty)
        var withTrays=snapshot
        var activity=IslandActivityTrayPreferences();activity.set(.timer,enabled:false);activity.place(.wellbeing,at:0)
        withTrays.activities=activity;withTrays.rotateActivities=true
        check(normalized.save(name:"With trays",snapshot:withTrays) == nil)
        let newStore=IslandSavedLayoutStore(defaults:defaults)
        check(newStore.layouts.first { $0.name == "With trays" }?.snapshot == withTrays)
        let trayLayout=newStore.layouts.first { $0.name == "With trays" }!
        check(newStore.rename(trayLayout.id,to:"Still has trays") == nil && newStore.layouts.first { $0.id==trayLayout.id }?.snapshot.activities == activity)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(withTrays)) as! [String:Any]
        legacy.removeValue(forKey:"activities");legacy.removeValue(forKey:"rotateActivities")
        let decoded=try JSONDecoder().decode(IslandDesignerSnapshot.self,from:JSONSerialization.data(withJSONObject:legacy))
        check(decoded.activities == nil && decoded.rotateActivities == nil && decoded.modules == snapshot.modules && decoded.canvas == snapshot.canvas)
        var damaged=withTrays;damaged.activities?.order=[.music,.music];damaged.activities?.enabled=[.music,.music];damaged.normalize()
        check(damaged.activities?.order.count==7 && damaged.activities?.enabled == [.music])
        newStore.delete(trayLayout.id);check(newStore.undoDelete() == nil && newStore.layouts.first { $0.id==trayLayout.id }?.snapshot == withTrays)
        print("PASS: \(count) production saved-layout checks; persistence, normalization, rename/update, duplicate names, limits, deletion undo across reload and unrelated data preservation; private test defaults only")
    }
}
