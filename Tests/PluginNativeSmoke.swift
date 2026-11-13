import Foundation
@main struct PluginNativeSmoke {
 @MainActor static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("IslandNativePlugin-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
  defer { try? FileManager.default.removeItem(at:root) }
  let b=IslandAgentBridge();b.root=root
  func event(_ kind:String="question",expires:Double=Date().timeIntervalSince1970+60,nonce:String=UUID().uuidString)->IslandAgentBridge.Event {
   let json:[String:Any]=["id":UUID().uuidString,"nonce":nonce,"provider":"chatgpt-plugin","event":"Question","session":"test","time":Date().timeIntervalSince1970,"expires":expires,"approval":false,"title":"Choose a colour","message":"","request":"","kind":kind,"options":["Blue","Green"],"state":"waiting"]
   return try! JSONDecoder().decode(IslandAgentBridge.Event.self,from:JSONSerialization.data(withJSONObject:json))
  }
  var count=0
  func check(_ value:Bool) { precondition(value,"Native plugin check \(count+1)");count+=1 }
  var question=event();b.events=[question]
  check(question.pending && question.isQuestion && question.isPlugin && question.statusTitle=="Your answer needed")
  check(question.providerName=="ChatGPT")
  check(b.answer(question,text:"  Green  "))
  let answerURL=root.appendingPathComponent("answers/"+question.id+".json"),answer=try JSONSerialization.jsonObject(with:Data(contentsOf:answerURL)) as! [String:Any]
  check(!b.answer(question,text:"Another answer"))
  check(answer["id"] as? String==question.id && answer["nonce"] as? String==question.nonce && answer["answer"] as? String=="Green")
  check((try FileManager.default.attributesOfItem(atPath:answerURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  check(!b.answer(question,text:" "))
  check(!b.answer(question,text:String(repeating:"x",count:8001)))
  b.events=[];check(!b.answer(question,text:"Blue"))
  b.events=[question];let old=event(expires:Date().timeIntervalSince1970-1);b.events=[old];check(!old.pending && !b.answer(old,text:"Blue"))
  let progress=event("progress");b.events=[progress];check(!progress.isQuestion && !b.answer(progress,text:"Blue"))
  question.resolution="Answered";b.events=[question];check(!question.pending && question.statusTitle=="Answered" && !b.answer(question,text:"Again"))
  question.resolution=nil;b.events=[question];var stale=question;stale.nonce=UUID().uuidString;check(!b.answer(stale,text:"Blue"))
  b.root=nil;check(!b.answer(question,text:"Blue"))
  print("PASS: \(count) production native plugin-question checks; real answer writer, matching nonce, pending status, expiry, blank/oversized replies and duplicate/stale replies")
 }
}
