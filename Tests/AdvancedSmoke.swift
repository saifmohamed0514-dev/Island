import Foundation
import CoreGraphics
@main struct AdvancedSmoke {
 static func main() {
    precondition(IslandPowerRules.arguments(enabled:true,onACPower:false) == ["-b","lowpowermode","1"])
    precondition(IslandPowerRules.arguments(enabled:false,onACPower:true) == ["-c","lowpowermode","0"])
    precondition(IslandPowerRules.validHash(String(repeating:"a",count:40)))
    precondition(!IslandPowerRules.validHash("x;rm -rf /"))
    precondition(!IslandPowerRules.validHash(String(repeating:"ａ",count:40)))
    let draft="Explain café & العربية? x=1 #test\nsecond line"
    let url=IslandChatGPTLinks.draft(draft)!,parts=URLComponents(url:url,resolvingAgainstBaseURL:false)!
    precondition(parts.scheme == "codex" && parts.host == "new" && parts.queryItems?.first?.value == draft)
    precondition(IslandChatGPTLinks.draft(String(repeating:"x",count:16001)) == nil)
    precondition(IslandChatGPTLinks.session("../../settings") == nil)
    precondition(IslandChatGPTLinks.session("019c6e27-e55b-73d1-87d8-4e01f1f75043")?.host == "threads")
    let frame=CGRect(x:-1920,y:1080,width:1920,height:1080)
    precondition(IslandSnapRules.layout(at:CGPoint(x:-1915,y:2100),in:frame) == .left)
    precondition(IslandSnapRules.layout(at:CGPoint(x:-1915,y:2155),in:frame) == .topLeft)
    precondition(IslandSnapRules.layout(at:CGPoint(x:-960,y:2155),in:frame) == .maximize)
    precondition(IslandSnapRules.layout(at:CGPoint(x:-960,y:1500),in:frame) == nil)
    precondition(IslandSnapRules.layout(at:CGPoint(x:5000,y:1500),in:frame) == nil)
    precondition(IslandDeviceAlertRules.shouldWarn(level:20,threshold:20,previous:21))
    precondition(!IslandDeviceAlertRules.shouldWarn(level:19,threshold:20,previous:20))
    precondition(!IslandDeviceAlertRules.shouldWarn(level:255,threshold:20,previous:nil))
    precondition(IslandDeviceAlertRules.shouldWarn(level:5,threshold:20,previous:nil))
    precondition(IslandReviewRules.endpoint(provider:"GitHub",repository:"owner/repo",page:2)?.query?.contains("page=2") == true)
    precondition(IslandReviewRules.endpoint(provider:"GitLab",repository:"owner/repo",page:1)?.absoluteString.contains("owner%2Frepo") == true)
    precondition(IslandReviewRules.endpoint(provider:"GitHub",repository:"owner/repo?secret=1",page:1) == nil)
    precondition(IslandReviewRules.endpoint(provider:"GitHub",repository:"owner/repo",page:0) == nil)
    precondition(IslandReviewRules.matchesReviewer(["requested_reviewers":[["login":"Saif"]]],provider:"GitHub",query:"saif"))
    precondition(!IslandReviewRules.matchesReviewer(["requested_reviewers":[["login":"other"]]],provider:"GitHub",query:"saif"))
    precondition(IslandReviewRules.matchesReviewer(["reviewers":[["uuid":"{fixture}"]]],provider:"Bitbucket",query:"{fixture}"))
    precondition(IslandReviewRules.jiraHost("fixture.atlassian.net") && !IslandReviewRules.jiraHost("fixture.atlassian.net.evil.test"))
    precondition(IslandReviewRules.issueKey("APP-123") && !IslandReviewRules.issueKey("../transitions"))
    let config=IslandAgentHookRules.openAI(baseCommand:"/fixture/IslandBridge --directory /fixture")
    let data=try! JSONSerialization.data(withJSONObject:config)
    let decoded=try! JSONSerialization.jsonObject(with:data) as! [String:Any]
    let hooks=decoded["hooks"] as! [String:[[String:Any]]]
    let timeouts=["SessionStart":60,"UserPromptSubmit":60,"PermissionRequest":60,"Stop":60,"Interrupt":3,"SessionEnd":3]
    precondition(Set(hooks.keys) == Set(timeouts.keys))
    for (event,timeout) in timeouts {
        let commands=hooks[event]!.first!["hooks"] as! [[String:Any]]
        precondition(commands.first!["timeout"] as? Int == timeout)
    }
    print("PASS: 34 power argument, ChatGPT URL/hook timeout, snap geometry, battery alert and provider-boundary checks")
 }
}
