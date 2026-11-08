import AppKit
import Defaults

// One feedback per meaningful action, with a short global rate limit so ring
// drags and edge previews feel precise rather than producing a constant buzz.
enum IslandHapticEvent { case selection,placement,confirmation,boundary }
enum IslandHapticRules {
    static func shouldPlay(enabled:Bool,now:Double,last:Double)->Bool { enabled && now.isFinite && now-last>=0.075 }
}
@MainActor enum IslandHaptics {
    private static var last = -Double.infinity
    static func play(_ event:IslandHapticEvent = .selection) {
        let now=ProcessInfo.processInfo.systemUptime
        guard IslandHapticRules.shouldPlay(enabled:Defaults[.enableHaptics],now:now,last:last) else { return };last=now
        let pattern:NSHapticFeedbackManager.FeedbackPattern
        switch event { case .selection,.boundary:pattern = .alignment;case .placement:pattern = .levelChange;case .confirmation:pattern = .generic }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern,performanceTime:.now)
    }
}
