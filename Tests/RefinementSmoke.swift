import Foundation
@main struct RefinementSmoke {
    static func main() {
        precondition(IslandUpdateRules.feed(repository:"owner/Island")?.absoluteString == "https://github.com/owner/Island/releases/latest/download/appcast.xml")
        precondition(IslandUpdateRules.feed(repository:"https://github.com/owner/Island.git") == IslandUpdateRules.feed(repository:"owner/Island"))
        for bad in ["TheBoredTeam/boring.notch","owner/repo?secret=1","https://evil.test/owner/repo","owner/../repo","a/b/c","owner/repo#tag"] { precondition(IslandUpdateRules.feed(repository:bad) == nil) }
        func allowed(_ mode:String="idle",_ idle:Double=300,_ hour:Int=12,_ setup:Bool=false,_ active:Bool=false,_ modal:Bool=false,_ timer:Bool=false,_ pending:Bool=false)->Bool { IslandUpdateRules.canInstall(mode:mode,idle:idle,hour:hour,setup:setup,active:active,modal:modal,timerRunning:timer,pendingRequests:pending) }
        precondition(allowed() && !allowed("quit") && !allowed("unknown"))
        precondition(!allowed("idle",299) && !allowed("idle",.nan))
        precondition(!allowed("idle",300,12,true) && !allowed("idle",300,12,false,true) && !allowed("idle",300,12,false,false,true))
        precondition(!allowed("idle",300,12,false,false,false,true) && !allowed("idle",300,12,false,false,false,false,true))
        precondition(allowed("night",300,22) && allowed("night",300,6) && !allowed("night",300,7) && !allowed("night",300,21))
        precondition(IslandHapticRules.shouldPlay(enabled:true,now:10,last:9.9))
        precondition(!IslandHapticRules.shouldPlay(enabled:true,now:10,last:9.98) && !IslandHapticRules.shouldPlay(enabled:false,now:10,last:0))
        precondition(IslandHapticRules.shouldPlay(enabled:true,now:10,last:-.infinity) && !IslandHapticRules.shouldPlay(enabled:true,now:.nan,last:0))
        precondition(IslandActivityRules.choose([],rotate:true,phase:1) == .idle)
        precondition(IslandActivityRules.choose([.music,.event,.notice],rotate:true,phase:4) == .event)
        precondition(IslandActivityRules.choose([.music,.event],rotate:false,phase:1) == .music)
        precondition(IslandActivityRules.excluded("com.apple.Music",from:"com.spotify.client, com.apple.Music"))
        precondition(!IslandActivityRules.excluded(nil,from:"") && !IslandActivityRules.excluded("com.apple.Music",from:"com.apple.Music.other"))
        let pages=IslandSettingsCatalog.groups.flatMap(\.pages)
        precondition(Set(pages.map(\.route)).count == pages.count)
        precondition(pages.contains { $0.route == "Updates" } && pages.contains { $0.route == "Live Activities" })
        precondition(pages.first(where:{ $0.route == "Permissions" }).map { IslandSettingsCatalog.matches($0,query:"privacy") } == true)
        precondition(pages.first(where:{ $0.route == "Behavior" }).map { IslandSettingsCatalog.matches($0,query:"HAPTICS") } == true)
        precondition(pages.first(where:{ $0.route == "Modules" }).map { IslandSettingsCatalog.matches($0,query:"arrange") } == true)
        print("PASS: 26 production update-consent scheduling, release URL, haptic throttling, live-activity and settings-search checks; no network, installs or hardware feedback")
    }
}
