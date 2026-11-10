import Foundation
@main struct GuidanceSmoke {
    static func main() {
        var checks=0
        func check(_ condition:Bool) { precondition(condition,"Guide check \(checks+1)");checks+=1 }
        let routes=IslandSettingsCatalog.groups.flatMap(\.pages).map(\.route)
        check(Set(routes) == Set(IslandGuideCatalog.pages.map(\.id)))
        check(Set(IslandGuideCatalog.pages.map(\.id)).count == routes.count)
        check(routes.allSatisfy { IslandGuideCatalog.page($0).id == $0 })
        check(IslandGuideCatalog.pages.allSatisfy { !$0.summary.isEmpty && !$0.steps.isEmpty && $0.steps.allSatisfy { !$0.isEmpty } })
        check(NotchViews.allCases.allSatisfy { let topic=IslandGuideCatalog.module($0);return topic.id == "module."+$0.rawValue && !topic.summary.isEmpty && topic.steps.count>=2 })
        check(IslandGuideCatalog.page("Focus & Sounds").matches("drag ring"))
        check(IslandGuideCatalog.page("System Controls").matches("HUD"))
        check(IslandGuideCatalog.page("System Controls").matches("low power"))
        check(IslandGuideCatalog.page("Modules").matches("SAVE arrangement"))
        check(IslandGuideCatalog.module(.shelf).matches("original file"))
        check(!IslandGuideCatalog.module(.shelf).matches("nonexistent phrase"))
        check(IslandGuideCatalog.page("Permissions").matches("   "))
        check(IslandSettingsCatalog.groups.flatMap(\.pages).first { $0.route == "System Controls" }.map { IslandSettingsCatalog.matches($0,query:"brightness volume") } == true)
        check(IslandGuideCatalog.page("unknown").id == "Overview")
        print("PASS: \(checks) production guidance checks; every Settings page/module covered, action/term search and mixed-case multiple-word queries; no OS requests")
    }
}
