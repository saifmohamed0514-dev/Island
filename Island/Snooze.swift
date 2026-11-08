import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let islandSnooze=Self("islandSnooze")
    static let islandNextModule=Self("islandNextModule")
    static let islandPreviousModule=Self("islandPreviousModule")
}
@MainActor final class IslandSnooze:ObservableObject {
    static let shared=IslandSnooze()
    @Published private(set) var active=false
    private var task:Task<Void,Never>?
    func toggle() {
        if active { resume();return }
        let minutes=max(1,min(120,UserDefaults.standard.object(forKey:"island.snooze.minutes") as? Int ?? 15))
        active=true;IslandHaptics.play(.confirmation)
        task=Task { try? await Task.sleep(for:.seconds(minutes*60));guard !Task.isCancelled else { return };active=false }
    }
    func resume() { task?.cancel();task=nil;active=false }
}
