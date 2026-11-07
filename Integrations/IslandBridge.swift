// Island local hook transport. No commands are executed here; approval is one request only.
import Foundation

struct IslandDecision:Decodable { let id:String; let nonce:String; let allow:Bool }

func argument(_ name:String) -> String? { guard let index = CommandLine.arguments.firstIndex(of:name), index+1 < CommandLine.arguments.count else { return nil }; return CommandLine.arguments[index+1] }
let provider = argument("--provider") ?? "relay"
let eventName = argument("--event") ?? "Notification"
let approval = ["claude","chatgpt","codex"].contains(provider) && eventName == "PermissionRequest" || provider == "cursor" && ["beforeShellExecution","beforeMCPExecution"].contains(eventName)
func result(_ allow:Bool? = nil) -> [String:Any] {
    guard approval else { return [:] }
    if provider == "cursor" { return ["permission":allow == true ? "allow" : "deny","user_message":allow == true ? "Approved once in Island." : "Not approved in Island."] }
    guard let allow else { return [:] } // Claude retains its own permission prompt on timeout.
    var decision:[String:Any] = ["behavior":allow ? "allow" : "deny"]
    if !allow { decision["message"] = "Declined in Island." }
    return ["hookSpecificOutput":["hookEventName":"PermissionRequest","decision":decision]]
}
func emit(_ object:[String:Any]) { if let data = try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]) { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) } }
func atomic(_ object:[String:Any],at url:URL) throws { let data = try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]); try data.write(to:url,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) }
func privateDirectory(_ url:URL) throws {
    if FileManager.default.fileExists(atPath:url.path) {
        let type = try FileManager.default.attributesOfItem(atPath:url.path)[.type] as? FileAttributeType
        guard type == .typeDirectory else { throw CocoaError(.fileReadNoPermission) }
    } else { try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path)
}
do {
    guard ["claude","cursor","chatgpt","codex","relay"].contains(provider), let directory = argument("--directory"), directory.hasPrefix("/") else { throw CocoaError(.fileReadInvalidFileName) }
    let root = URL(fileURLWithPath:directory,isDirectory:true); let events = root.appendingPathComponent("events",isDirectory:true); let decisions = root.appendingPathComponent("decisions",isDirectory:true)
    try privateDirectory(events); try privateDirectory(decisions)
    var input = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount:8192), !chunk.isEmpty { input.append(chunk); if input.count > 1_048_576 { throw CocoaError(.fileReadTooLarge) } }
    guard let object = try JSONSerialization.jsonObject(with:input) as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }
    let id = UUID().uuidString; let nonce = UUID().uuidString
    let timeout = min(50,max(0.1,Double(argument("--timeout") ?? "40") ?? 40))
    let now = Date().timeIntervalSince1970
    let tool = object["tool_name"] as? String ?? (provider == "cursor" ? "Shell / MCP" : "Agent")
    var request:[String:Any] = ["tool":tool]
    if let value = object["tool_input"] { request["input"] = value }
    if let value = object["command"] { request["command"] = value }
    if let value = object["cwd"] { request["workingDirectory"] = value }
    if let value = object["turn_id"] { request["turn"] = value }
    let requestData = try JSONSerialization.data(withJSONObject:request,options:[.prettyPrinted,.sortedKeys])
    let complete = requestData.count <= 65536
    let message = String((object["message"] as? String ?? object["last_assistant_message"] as? String ?? "").prefix(4000))
    var record:[String:Any] = ["id":id,"nonce":nonce,"provider":provider,"event":eventName,"session":object["session_id"] as? String ?? object["conversation_id"] as? String ?? "","time":now,"expires":now+timeout,"approval":approval && complete,"title":approval ? tool : eventName,"message":message,"request":complete ? String(data:requestData,encoding:.utf8)! : "Request too large. Review it in the original client."]
    if provider == "relay" { record["title"] = String((object["title"] as? String ?? "Notice").prefix(300)); record["message"] = String((object["body"] as? String ?? message).prefix(4000)) }
    let file = events.appendingPathComponent(id+".island-event.json")
    try atomic(record,at:file)
    // Bound only this transport's own event history. Pending decisions expire before these limits.
    let oldFiles = (try? FileManager.default.contentsOfDirectory(at:events,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
    let own = oldFiles.filter { file in file.lastPathComponent.hasSuffix(".island-event.json") && UUID(uuidString:String(file.lastPathComponent.prefix(36))) != nil }.sorted {
        ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
    }
    for (index,old) in own.enumerated() where old != file {
        let modified = (try? old.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if Date().timeIntervalSince(modified) > 86400 || index < own.count-500 { try? FileManager.default.removeItem(at:old) }
    }
    guard approval && complete else { emit(result()); exit(0) }
    let response = decisions.appendingPathComponent(id+".json")
    var answer:Bool?
    while Date().timeIntervalSince1970 < now+timeout {
        if let data = try? Data(contentsOf:response), let decision = try? JSONDecoder().decode(IslandDecision.self,from:data), decision.id == id, decision.nonce == nonce { answer = decision.allow; break }
        Thread.sleep(forTimeInterval:0.1)
    }
    record["approval"] = false; record["resolution"] = answer == true ? "Allowed once" : answer == false ? "Declined" : "Review in original client"
    try atomic(record,at:file); try? FileManager.default.removeItem(at:response); emit(result(answer))
} catch { emit(result()) }
