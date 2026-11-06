import Foundation
final class CompletionDefaults:UserDefaults,@unchecked Sendable {
    var values:[String:Any] = [:]
    override func object(forKey key:String) -> Any? { values[key] }
    override func set(_ value:Any?,forKey key:String) { values[key] = value }
    override func string(forKey key:String) -> String? { values[key] as? String }
    override func data(forKey key:String) -> Data? { values[key] as? Data }
    override func array(forKey key:String) -> [Any]? { values[key] as? [Any] }
    override func integer(forKey key:String) -> Int { values[key] as? Int ?? 0 }
    override func double(forKey key:String) -> Double { values[key] as? Double ?? 0 }
    override func bool(forKey key:String) -> Bool { values[key] as? Bool ?? false }
}
@main struct CompletionSmoke {
    @MainActor static func main() async throws {
        let defaults = CompletionDefaults(); defaults.set("Silent",forKey:"island.timer.tone")
        let timer = IslandFocusTimer(defaults:defaults,startClock:false)
        timer.state.deadline = Date().addingTimeInterval(-1)
        timer.tick()
        precondition(timer.state.finished && timer.showCompletion)
        try await Task.sleep(for:.seconds(4.2))
        precondition(!timer.showCompletion && timer.state.finished)
        timer.tick(); precondition(!timer.showCompletion)
        timer.addPreset(90)
        let restored = IslandFocusTimer(defaults:defaults,startClock:false)
        precondition(restored.state.finished && !restored.showCompletion)
        precondition(restored.presets.contains(90))
        restored.reset(minutes:5); precondition(!restored.showCompletion && !restored.state.finished)
        defaults.set(true,forKey:"island.timer.pomodoro")
        restored.state.deadline = Date().addingTimeInterval(-1); restored.tick()
        precondition(restored.phase == "Break" && restored.state.deadline != nil && restored.state.duration == 300)
        print("PASS: 7 actual completion, relaunch, preset and work/break checks")
    }
}
