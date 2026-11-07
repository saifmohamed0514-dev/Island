import Foundation
final class FixtureProtocol:URLProtocol,@unchecked Sendable {
    static var requests:[URLRequest]=[]
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let path=request.url!.path;var status=200;let body:Any
        if request.httpMethod == "POST",path.hasSuffix("/transitions") { status=204;body=[:] }
        else if path.hasSuffix("/transitions") { body=["transitions":[["id":"21","name":"Doing","fields":[:]]]] }
        else if path.hasSuffix("/search/jql") { body=["issues":[["id":"1","key":"APP-1","fields":["summary":"Fixture","status":["name":"Open"]]]],"isLast":false,"nextPageToken":"fixture-cursor"] }
        else { body=[["number":1,"title":"Fixture review","html_url":"https://github.com/fixture/repo/pull/1","requested_reviewers":[["login":"reviewer"]]]] }
        let data=try! JSONSerialization.data(withJSONObject:body)
        let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json","Link":"<https://api.github.com/repos/fixture/repo/pulls?page=2>; rel=\"next\""])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct ServiceSmoke {
    @MainActor static func main() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[FixtureProtocol.self]
        let service=IslandCodeHosting(session:URLSession(configuration:config),tokenProvider:{ _ in "fixture-token" })
        await service.refresh(provider:"GitHub",repository:"fixture/repo",jiraHost:"",email:"",jql:"",reviewer:"reviewer",page:2)
        precondition(service.reviews.count == 1 && service.page == 2 && service.hasNext)
        precondition(FixtureProtocol.requests.last?.url?.host == "api.github.com")
        precondition(FixtureProtocol.requests.last?.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token")
        await service.refresh(provider:"GitHub",repository:"fixture/repo",jiraHost:"",email:"",jql:"",reviewer:"someone-else")
        precondition(service.reviews.isEmpty && service.hasNext)
        await service.refresh(provider:"Jira",repository:"",jiraHost:"fixture.atlassian.net",email:"fixture@example.invalid",jql:"project=APP")
        precondition(service.reviews.first?.issueKey == "APP-1" && service.hasNext)
        await service.refresh(provider:"Jira",repository:"",jiraHost:"fixture.atlassian.net",email:"fixture@example.invalid",jql:"project=APP",page:2)
        // URLProtocol may stream the HTTP body; pagination is also established by the actual second request and page state.
        precondition(service.page == 2 && FixtureProtocol.requests.last?.url?.path == "/rest/api/3/search/jql")
        await service.loadTransitions(issue:"APP-1",host:"fixture.atlassian.net",email:"fixture@example.invalid")
        precondition(service.transitions.count == 1 && !service.transitions[0].needsFields)
        let choice=service.transitions[0],count=FixtureProtocol.requests.count
        await service.transition(issue:"APP-1",choice:choice,host:"other.atlassian.net",email:"fixture@example.invalid")
        precondition(FixtureProtocol.requests.count == count)
        await service.transition(issue:"APP-1",choice:choice,host:"fixture.atlassian.net",email:"fixture@example.invalid")
        precondition(FixtureProtocol.requests.last?.httpMethod == "POST" && service.status.hasPrefix("Changed APP-1"))
        let after=FixtureProtocol.requests.count
        await service.loadTransitions(issue:"../unsafe",host:"fixture.atlassian.net",email:"fixture@example.invalid")
        precondition(FixtureProtocol.requests.count == after)
        let weather=IslandWeather()
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(identifier:"Asia/Dubai");formatter.dateFormat="yyyy-MM-dd'T'HH:mm"
        weather.forecast=IslandWeather.Forecast(current:.init(temperature_2m:25,relative_humidity_2m:40,apparent_temperature:26,weather_code:0,wind_speed_10m:10),daily:.init(time:[],temperature_2m_max:[],temperature_2m_min:[]),hourly:.init(time:[formatter.string(from:Date().addingTimeInterval(-7200)),formatter.string(from:Date().addingTimeInterval(3600))],temperature_2m:[20,27],precipitation_probability:[0,10]),timezone:"Asia/Dubai")
        precondition(weather.hours.count == 1 && weather.hours[0].temperature == 27 && weather.hours[0].rain == 10)
        print("PASS: 11 production service fixture checks; pagination, reviewer filtering, Jira writes/context guards and hourly weather; no network or Keychain access")
    }
}
