import Foundation

enum IslandReviewRules {
    static func endpoint(provider:String,repository:String,page:Int) -> URL? {
        let segments=repository.split(separator:"/",omittingEmptySubsequences:false)
        guard ["GitHub","GitLab","Bitbucket"].contains(provider),(2...10).contains(segments.count),(provider == "GitLab" || segments.count == 2),segments.allSatisfy({ $0 != "." && $0 != ".." && $0.range(of:#"^[A-Za-z0-9_.-]+$"#,options:.regularExpression) != nil }),(1...10000).contains(page) else { return nil }
        let base:String
        var query:[URLQueryItem]
        switch provider {
        case "GitLab":base="https://gitlab.com/api/v4/projects/"+repository.replacingOccurrences(of:"/",with:"%2F")+"/merge_requests";query=[URLQueryItem(name:"state",value:"opened"),URLQueryItem(name:"per_page",value:"30"),URLQueryItem(name:"order_by",value:"updated_at"),URLQueryItem(name:"sort",value:"desc")]
        case "Bitbucket":base="https://api.bitbucket.org/2.0/repositories/\(repository)/pullrequests";query=[URLQueryItem(name:"state",value:"OPEN"),URLQueryItem(name:"pagelen",value:"30"),URLQueryItem(name:"sort",value:"-updated_on")]
        default:base="https://api.github.com/repos/\(repository)/pulls";query=[URLQueryItem(name:"state",value:"open"),URLQueryItem(name:"per_page",value:"30"),URLQueryItem(name:"sort",value:"updated"),URLQueryItem(name:"direction",value:"desc")]
        }
        var components=URLComponents(string:base);query.append(URLQueryItem(name:"page",value:String(page)));components?.queryItems=query;return components?.url
    }
    static func matchesReviewer(_ item:[String:Any],provider:String,query:String)->Bool {
        let wanted=query.trimmingCharacters(in:.whitespacesAndNewlines).lowercased();guard !wanted.isEmpty else { return true }
        let reviewers=(item[provider == "GitHub" ? "requested_reviewers" : "reviewers"] as? [[String:Any]]) ?? []
        return reviewers.contains { person in ["login","username","nickname","uuid","account_id","display_name","name"].contains { key in (person[key] as? String)?.lowercased() == wanted } }
    }
    static func jiraHost(_ host:String)->Bool { host.range(of:#"^[A-Za-z0-9-]+\.atlassian\.net$"#,options:.regularExpression) != nil }
    static func issueKey(_ key:String)->Bool { key.range(of:#"^[A-Za-z][A-Za-z0-9_]*-[0-9]+$"#,options:.regularExpression) != nil }
}
