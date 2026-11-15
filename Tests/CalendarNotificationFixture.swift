import Foundation
// Native notification boundary only. Production scheduling code is compiled unchanged.
enum FixtureAuthorization { case authorized,provisional,denied }
struct FixtureNotificationSettings { let authorizationStatus:FixtureAuthorization }
struct UNNotificationSound { static let `default`=UNNotificationSound() }
final class UNMutableNotificationContent { var title="";var body="";var sound:UNNotificationSound? }
struct UNTimeIntervalNotificationTrigger { let timeInterval:Double;let repeats:Bool }
struct UNNotificationRequest { let identifier:String;let content:UNMutableNotificationContent;let trigger:UNTimeIntervalNotificationTrigger? }
@MainActor final class UNUserNotificationCenter {
 static let fixture=UNUserNotificationCenter()
 static func current()->UNUserNotificationCenter { fixture }
 var pending:[UNNotificationRequest]=[]
 var added:[String]=[]
 var authorization=FixtureAuthorization.authorized
 var holdNextAdd=false
 private var held:CheckedContinuation<Void,Never>?
 private var started:CheckedContinuation<Void,Never>?
 func reset() { pending=[UNNotificationRequest(identifier:"foreign-timer",content:UNMutableNotificationContent(),trigger:nil)];added=[];authorization = .authorized }
 func pendingNotificationRequests() async ->[UNNotificationRequest] { pending }
 func notificationSettings() async ->FixtureNotificationSettings { .init(authorizationStatus:authorization) }
 func removePendingNotificationRequests(withIdentifiers ids:[String]) { pending.removeAll { ids.contains($0.identifier) } }
 func add(_ request:UNNotificationRequest) async throws {
  if holdNextAdd { holdNextAdd=false;await withCheckedContinuation { held=$0;started?.resume();started=nil } }
  pending.removeAll { $0.identifier==request.identifier };pending.append(request);added.append(request.identifier)
 }
 func waitUntilHeld() async { if held != nil { return };await withCheckedContinuation { started=$0 } }
 func releaseHeldAdd() { held?.resume();held=nil }
}
