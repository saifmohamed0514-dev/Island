// Hook-free local MCP transport. No provider credentials, network or commands.
import Foundation
import CoreFoundation
import Darwin

func arg(_ key:String)->String? { guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else { return nil };return CommandLine.arguments[i+1] }
final class IslandPluginServer:@unchecked Sendable {
let provider:String
let root:URL
init(provider:String,path:String) { self.provider=provider;root=URL(fileURLWithPath:path,isDirectory:true) }
let files=FileManager.default,outputLock=NSLock(),stateLock=NSLock()
var lastCleanup=Date.distantPast
var stopped=false,cancelled=Set<String>(),sessions:[String:String]=[:],questions=Set<String>()
let questionSlots=DispatchSemaphore(value:8)
let connectionID=UUID().uuidString
func privateFolder(_ url:URL) throws {
    if !files.fileExists(atPath:url.path) { try files.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
    let a=try files.attributesOfItem(atPath:url.path)
    guard a[.type] as? FileAttributeType == .typeDirectory,(a[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),((a[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else { throw CocoaError(.fileReadNoPermission) }
}
func write(_ value:[String:Any],to url:URL) throws {
    if files.fileExists(atPath:url.path),try files.attributesOfItem(atPath:url.path)[.type] as? FileAttributeType != .typeRegular { throw CocoaError(.fileReadNoPermission) }
    let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]);try data.write(to:url,options:.atomic);try files.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
}
func send(_ value:[String:Any]) { guard let data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else { return };outputLock.lock();defer { outputLock.unlock() };FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10])) }
func reply(_ id:Any,_ result:[String:Any]) { send(["jsonrpc":"2.0","id":id,"result":result]) }
func error(_ id:Any,_ code:Int,_ message:String) { send(["jsonrpc":"2.0","id":id,"error":["code":code,"message":message]]) }
func toolResult(_ id:Any,_ value:[String:Any],failed:Bool=false) { let text=(try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])).flatMap { String(data:$0,encoding:.utf8) } ?? "{}";reply(id,["content":[["type":"text","text":text]],"structuredContent":value,"isError":failed]) }
func string(_ a:[String:Any],_ key:String,_ limit:Int)->String? { guard let s=a[key] as? String,!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,s.utf8.count<=limit else { return nil };return s }
func number(_ value:Any?)->Double? { guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else { return nil };return n.doubleValue }
func available()->Bool {
    let url=root.appendingPathComponent("presence.json")
    guard let a=try? files.attributesOfItem(atPath:url.path),a[.type] as? FileAttributeType == .typeRegular,(a[.size] as? NSNumber)?.intValue ?? 99999<4096,let d=try? Data(contentsOf:url),let o=try? JSONSerialization.jsonObject(with:d) as? [String:Any],let time=number(o["time"]) else { return false }
    return (0...8).contains(Date().timeIntervalSince1970-time)
}
func record(id:String,session:String,kind:String,title:String,message:String,state:String,expires:Double,extra:[String:Any]=[:]) throws -> [String:Any] {
    var value:[String:Any]=["id":id,"nonce":UUID().uuidString,"provider":provider,"event":kind == "question" ? "Question" : "Progress","session":session,"time":Date().timeIntervalSince1970,"expires":expires,"approval":false,"title":title,"message":message,"request":"","kind":kind,"state":state]
    for (k,v) in extra { value[k]=v }
    try write(value,to:root.appendingPathComponent("events/"+id+".island-event.json"));return value
}
func cleanup() {
    stateLock.lock();guard Date().timeIntervalSince(lastCleanup)>60 else { stateLock.unlock();return };lastCleanup=Date();stateLock.unlock()
    let directory=root.appendingPathComponent("events")
    let own=((try? files.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []).filter { $0.lastPathComponent.hasSuffix(".island-event.json") && UUID(uuidString:String($0.lastPathComponent.dropLast(".island-event.json".count))) != nil }.sorted { ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)<((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    for (index,url) in own.enumerated() {
        let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        guard Date().timeIntervalSince(date)>86400 || index<own.count-500 else { continue }
        if let data=try? Data(contentsOf:url),let record=try? JSONSerialization.jsonObject(with:data) as? [String:Any],record["kind"] as? String == "question",(number(record["expires"]) ?? 0)>Date().timeIntervalSince1970 { continue }
        try? files.removeItem(at:url)
    }
}
func connection(_ state:String) { if state == "connected" && isCancelled(connectionID) { return };cleanup();_ = try? record(id:connectionID,session:connectionID,kind:"connection",title:"Plugin connected",message:"",state:state,expires:Date().timeIntervalSince1970+20) }
func isCancelled(_ key:String)->Bool { stateLock.lock();defer { stateLock.unlock() };return stopped || cancelled.contains(key) }
func taskID(_ args:[String:Any])->String? { guard let value=string(args,"task_id",100),value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }) else { return nil };return value }
let schema:[String:Any]=["type":"object","properties":["task_id":["type":"string","description":"Stable short ID for this task. Letters, digits, dash, dot or underscore."],"title":["type":"string"],"message":["type":"string"],"state":["type":"string","enum":["working","completed","failed","cancelled"]],"percent":["type":"number","minimum":0,"maximum":100]],"required":["task_id","title","state"],"additionalProperties":false]
let questionSchema:[String:Any]=["type":"object","properties":["task_id":["type":"string"],"question":["type":"string"],"options":["type":"array","items":["type":"string"],"maxItems":6],"timeout_seconds":["type":"number","minimum":5,"maximum":300]],"required":["task_id","question"],"additionalProperties":false]
var tools:[[String:Any]] { [
 ["name":"report_progress","description":"Show a real task update in the local Island notch. Call at the start, at meaningful milestones, and on completion/failure. Do not invent a percentage.","inputSchema":schema,"annotations":["readOnlyHint":false,"destructiveHint":false,"openWorldHint":false]],
 ["name":"ask_question","description":"Ask a clarification or preference question in Island and wait for the user's answer. Not for credentials, OS permission or authorizing tool execution. If unanswered, ask in the chat instead.","inputSchema":questionSchema,"annotations":["readOnlyHint":false,"destructiveHint":false,"openWorldHint":false]],
 ["name":"connection_status","description":"Check whether the Island app is connected and able to show plugin activity.","inputSchema":["type":"object","properties":[:],"additionalProperties":false],"annotations":["readOnlyHint":true,"openWorldHint":false]]
] }
func handle(_ object:[String:Any]) {
    guard object["jsonrpc"] as? String == "2.0",let method=object["method"] as? String else { error(object["id"] ?? NSNull(),-32600,"Invalid request");return }
    let params=object["params"] as? [String:Any] ?? [:]
    if method == "notifications/cancelled",let id=params["requestId"] { stateLock.lock();if questions.contains(String(describing:id)) { cancelled.insert(String(describing:id)) };stateLock.unlock();return }
    guard let id=object["id"] else { return }
    guard id is String || number(id) != nil else { error(NSNull(),-32600,"Invalid request ID");return }
    switch method {
    case "initialize":
        let version=params["protocolVersion"] as? String ?? "2025-06-18"
        reply(id,["protocolVersion":["2024-11-05","2025-03-26","2025-06-18","2025-11-25"].contains(version) ? version : "2025-06-18","capabilities":["tools":["listChanged":false]],"serverInfo":["name":"island","version":"2.10.0"],"instructions":"Use report_progress for task milestones. Use ask_question for user preferences/clarifications, never passwords or native security approvals. Progress covers only this plugin's tasks."])
        connection("connected")
    case "ping":reply(id,[:])
    case "tools/list":reply(id,["tools":tools])
    case "tools/call":
        let name=params["name"] as? String ?? "",a=params["arguments"] as? [String:Any] ?? [:]
        if name == "connection_status" { toolResult(id,["available":available(),"provider":provider]);return }
        guard name == "report_progress" || name == "ask_question" else { error(id,-32602,"Unknown tool");return }
        guard let task=taskID(a) else { toolResult(id,["error":"Invalid task ID"],failed:true);return }
        do {
            if name == "report_progress" {
                guard let title=string(a,"title",300),let state=a["state"] as? String,["working","completed","failed","cancelled"].contains(state),(a["message"] == nil || a["message"] is String),(a["message"] as? String ?? "").utf8.count<=4000 else { throw CocoaError(.fileReadCorruptFile) }
                var extra:[String:Any]=[:]
                if let raw=a["percent"] { guard let percent=number(raw),(0...100).contains(percent) else { throw CocoaError(.fileReadCorruptFile) };extra["percent"]=percent }
                stateLock.lock();if sessions.count>=100 && sessions[task]==nil { stateLock.unlock();throw CocoaError(.fileReadTooLarge) };let eventID=sessions[task] ?? UUID().uuidString;sessions[task]=eventID;stateLock.unlock()
                _=try record(id:eventID,session:task,kind:"progress",title:title,message:a["message"] as? String ?? "",state:state,expires:Date().timeIntervalSince1970+300,extra:extra)
                toolResult(id,["recorded":true,"visible":available()]);return
            }
            guard questionSlots.wait(timeout:.now()) == .success else { toolResult(id,["answered":false,"reason":"Too many pending questions. Ask in chat."],failed:true);return };defer { questionSlots.signal() }
            guard available() else { toolResult(id,["answered":false,"reason":"Island is not connected. Ask in the original chat."],failed:true);return }
            guard let question=string(a,"question",2000) else { throw CocoaError(.fileReadCorruptFile) }
            let options=a["options"] as? [String] ?? []
            guard a["options"] == nil || a["options"] is [String],options.count<=6,options.allSatisfy({ !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count<=300 }),Set(options).count==options.count else { throw CocoaError(.fileReadCorruptFile) }
            let timeout=number(a["timeout_seconds"]) ?? 120
            guard (5...300).contains(timeout),a["timeout_seconds"] == nil || number(a["timeout_seconds"]) != nil else { throw CocoaError(.fileReadCorruptFile) }
            let eventID=UUID().uuidString,key=String(describing:id),deadline=Date().timeIntervalSince1970+timeout
            stateLock.lock();questions.insert(key);stateLock.unlock()
            var event=try record(id:eventID,session:task,kind:"question",title:question,message:"",state:"waiting",expires:deadline,extra:["options":options])
            let response=root.appendingPathComponent("answers/"+eventID+".json")
            defer { stateLock.lock();cancelled.remove(key);questions.remove(key);stateLock.unlock() }
            var answered:String?,lastProgress=Date.distantPast,reason="Timed out. Ask in the original chat."
            while Date().timeIntervalSince1970<deadline {
                if isCancelled(key) { reason="Cancelled";break }
                if !available() { reason="Island disconnected. Ask in the original chat.";break }
                if let attributes=try? files.attributesOfItem(atPath:response.path),attributes[.type] as? FileAttributeType == .typeRegular,(attributes[.size] as? NSNumber)?.intValue ?? 99999<=32768,let data=try? Data(contentsOf:response),let answer=try? JSONSerialization.jsonObject(with:data) as? [String:Any],answer["id"] as? String==eventID,answer["nonce"] as? String==event["nonce"] as? String,let text=string(answer,"answer",8000) { answered=text;break }
                if Date().timeIntervalSince(lastProgress)>5,let meta=params["_meta"] as? [String:Any],let token=meta["progressToken"] { send(["jsonrpc":"2.0","method":"notifications/progress","params":["progressToken":token,"progress":timeout-(deadline-Date().timeIntervalSince1970),"total":timeout,"message":"Waiting for your answer in Island"]]);lastProgress=Date() }
                Thread.sleep(forTimeInterval:0.1)
            }
            event["state"]=answered == nil ? "cancelled" : "completed";event["resolution"]=answered == nil ? reason : "Answered";event["time"]=Date().timeIntervalSince1970
            try write(event,to:root.appendingPathComponent("events/"+eventID+".island-event.json"));try? files.removeItem(at:response)
            if let answered { toolResult(id,["answered":true,"answer":answered]) } else { toolResult(id,["answered":false,"reason":reason],failed:true) }
        } catch { toolResult(id,["error":"Invalid or unavailable local plugin request"],failed:true) }
    default:error(id,-32601,"Method not found")
    }
}
func run() {
do { try privateFolder(root);try privateFolder(root.appendingPathComponent("events"));try privateFolder(root.appendingPathComponent("answers")) } catch { exit(3) }
let heartbeat=DispatchSource.makeTimerSource(queue:.global(qos:.utility));heartbeat.schedule(deadline:.now(),repeating:5);heartbeat.setEventHandler { [self] in connection("connected") };heartbeat.resume()
var input=Data()
var bytes=[UInt8](repeating:0,count:8192)
while true {
    let length=Darwin.read(STDIN_FILENO,&bytes,bytes.count)
    if length==0 { break }
    if length<0 { if errno==EINTR { continue };break }
    input.append(contentsOf:bytes.prefix(length))
    while let end=input.firstIndex(of:10) {
        let line=Data(input[..<end]);input.removeSubrange(...end)
        guard line.count<=1_048_576 else { error(NSNull(),-32600,"Request too large");continue }
        guard let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] else { error(NSNull(),-32700,"Invalid JSON");continue }
        DispatchQueue.global(qos:.userInitiated).async { [self] in handle(object) }
    }
    if input.count>1_048_576 { error(NSNull(),-32600,"Request too large");break }
}
stateLock.lock();stopped=true;stateLock.unlock();heartbeat.cancel();connection("disconnected")
// Let pending tools mark cancellation before this local transport exits.
Thread.sleep(forTimeInterval:0.25)

}
}
let provider=arg("--provider") ?? ""
guard ["chatgpt-plugin","claude-plugin"].contains(provider),let path=arg("--directory"),path.hasPrefix("/") else { exit(2) }
IslandPluginServer(provider:provider,path:path).run()
