import SwiftUI
import Combine
import UserNotifications

@MainActor final class IslandNotices:ObservableObject {
    static let shared=IslandNotices()
    struct Notice:Codable,Identifiable { var id:String;var title:String;var body:String;var source:String;var date:Date;var read:Bool }
    @Published private(set) var items:[Notice]=[]
    init() { items=UserDefaults.standard.data(forKey:"island.notices").flatMap { try? JSONDecoder().decode([Notice].self,from:$0) } ?? [] }
    func post(title:String,body:String,source:String) {
        let item=Notice(id:UUID().uuidString,title:title,body:body,source:source,date:Date(),read:false)
        items.insert(item,at:0);items=Array(items.prefix(100));save()
        let content=UNMutableNotificationContent();content.title=title;content.body=body;content.sound = .default
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:item.id,content:content,trigger:nil))
        }
    }
    func markRead() { for index in items.indices { items[index].read=true };save() }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(items),forKey:"island.notices") }
    func requestPermission() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])) ?? false }
}
enum IslandDeviceAlertRules {
    static func shouldWarn(level:Int,threshold:Int,previous:Int?)->Bool {
        guard (0...100).contains(level) else { return false }
        let threshold=min(50,max(5,threshold));return level <= threshold && (previous == nil || previous! > threshold)
    }
}
