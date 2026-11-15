import Foundation
import Combine
import UserNotifications

@MainActor final class IslandCalendarAlerts:ObservableObject {
    static let shared=IslandCalendarAlerts()
    private var task:Task<Void,Never>?
    private var revision=0
    private var lastPlan:[IslandCalendarReminder]?
    @Published private(set) var status=""
    func configure(_ events:[IslandCalendarItem],preferences:IslandCalendarPreferences) {
        revision+=1;let requested=revision,previous=task
        // Wait for an in-flight native add before removing/replacing our own alerts.
        // This prevents a late old add from restoring a disabled reminder.
        task=Task { [weak self] in
            await previous?.value
            guard let self,self.revision==requested else { return }
            let center=UNUserNotificationCenter.current()
            let pending=await center.pendingNotificationRequests()
            guard self.revision==requested else { return }
            let ownIDs=pending.filter { $0.identifier.hasPrefix("IslandCalendarLeave-") }.map(\.identifier)
            guard preferences.leaveReminders else { center.removePendingNotificationRequests(withIdentifiers:ownIDs);self.lastPlan=[];self.status="Leave reminders are off.";return }
            let status=await center.notificationSettings()
            guard self.revision==requested else { return }
            guard status.authorizationStatus == .authorized || status.authorizationStatus == .provisional else { center.removePendingNotificationRequests(withIdentifiers:ownIDs);self.lastPlan=nil;self.status="Allow Notifications in Permissions to receive these reminders.";return }
            let plan=IslandCalendarRules.reminders(events,preferences:preferences)
            if self.lastPlan==plan && Set(ownIDs)==Set(plan.map(\.id)) { self.status="\(plan.count) reminders queued.";return }
            center.removePendingNotificationRequests(withIdentifiers:ownIDs)
            self.lastPlan=plan
            var successes=0
            for reminder in plan {
                guard self.revision==requested else { return }
                let delay=reminder.fire.timeIntervalSinceNow;guard delay>0 else { continue }
                let content=UNMutableNotificationContent();content.title="Time to get ready";content.body=reminder.body;content.sound = .default
                do { try await center.add(UNNotificationRequest(identifier:reminder.id,content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:max(1,delay),repeats:false)));successes+=1 }
                catch { self.lastPlan=nil }
            }
            if self.revision==requested { self.status=successes==plan.count ? "\(successes) reminders queued. macOS notification and Focus choices still apply." : "Some reminders couldn’t be queued. Check Notifications and try refreshing Calendar." }
        }
    }
}
