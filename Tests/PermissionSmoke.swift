import Foundation
@MainActor final class PermissionFixtureClient:IslandPermissionClient {
    var values=Dictionary(uniqueKeysWithValues:IslandPermission.allCases.map { ($0,IslandPermissionStatus.ask) })
    var requests:[IslandPermission]=[]
    var waiting:Set<IslandPermission>=[]
    var declining:Set<IslandPermission>=[]
    var hold:IslandPermission?
    var continuation:CheckedContinuation<Void,Never>?
    var inFlight=0,maxInFlight=0
    func snapshot() async -> [IslandPermission:IslandPermissionStatus] { values }
    func request(_ key:IslandPermission) async -> IslandPermissionAttempt {
        requests.append(key);inFlight+=1;maxInFlight=max(maxInFlight,inFlight);defer { inFlight-=1 }
        if hold == key { await withCheckedContinuation { continuation=$0 } }
        if waiting.contains(key) { return .waitingInSettings }
        values[key] = declining.contains(key) ? .settings : .allowed
        return .finished
    }
    func release() { continuation?.resume();continuation=nil }
}
@main struct PermissionSmoke {
    @MainActor static func main() async {
        let client=PermissionFixtureClient(),setup=IslandPermissionSetup(client:client)
        await setup.refresh();precondition(client.requests.isEmpty)
        client.values[.camera] = .allowed;client.values[.focus] = .restricted;client.values[.spotify] = .unavailable
        await setup.refresh();setup.selected=[.music,.calendar,.accessibility,.camera,.focus,.spotify]
        await setup.begin()
        precondition(client.requests == [.accessibility,.calendar,.music])
        precondition(!setup.running && setup.remaining.isEmpty && client.maxInFlight == 1)
        precondition(!IslandPermissionStatus.checking.canSetUp && !IslandPermissionStatus.allowed.canSetUp && !IslandPermissionStatus.restricted.canSetUp && !IslandPermissionStatus.unavailable.canSetUp)
        precondition(IslandPermissionStatus.needsPlayer.canSetUp)
        precondition(IslandPermission.allCases.allSatisfy { $0.settingsURL.scheme == "x-apple.systempreferences" })

        let manual=PermissionFixtureClient(),guided=IslandPermissionSetup(client:manual)
        manual.values[.calendar] = .settings;manual.waiting=[.calendar]
        await guided.refresh();await guided.begin([.calendar,.reminders])
        precondition(guided.running && guided.waiting && guided.current == .calendar && manual.requests == [.calendar])
        manual.values[.calendar] = .allowed;await guided.refresh()
        precondition(!guided.running && manual.requests == [.calendar,.reminders])

        let skipped=PermissionFixtureClient(),skipSetup=IslandPermissionSetup(client:skipped)
        skipped.waiting=[.accessibility]
        await skipSetup.refresh();await skipSetup.begin([.accessibility,.camera]);await skipSetup.skip()
        precondition(!skipSetup.running && skipped.requests == [.accessibility,.camera] && skipped.values[.accessibility] == .ask)

        let retried=PermissionFixtureClient(),retrySetup=IslandPermissionSetup(client:retried)
        retried.waiting=[.accessibility]
        await retrySetup.refresh();await retrySetup.begin([.accessibility]);retried.waiting=[];await retrySetup.retry()
        precondition(!retrySetup.running && retried.requests == [.accessibility,.accessibility] && retrySetup.status(.accessibility) == .allowed)

        let declined=PermissionFixtureClient(),declinedSetup=IslandPermissionSetup(client:declined)
        declined.declining=[.camera]
        await declinedSetup.refresh();await declinedSetup.begin([.camera,.notifications])
        precondition(declinedSetup.status(.camera) == .settings && declinedSetup.status(.notifications) == .allowed && declined.requests == [.camera,.notifications])

        let held=PermissionFixtureClient(),cancelled=IslandPermissionSetup(client:held)
        held.hold = .camera;await cancelled.refresh()
        let pending=Task { await cancelled.begin([.camera,.calendar]) }
        while held.continuation == nil { await Task.yield() }
        held.values[.camera] = .allowed;await cancelled.refresh()
        precondition(cancelled.prompting && held.requests == [.camera])
        cancelled.stop();await cancelled.begin([.reminders])
        precondition(cancelled.prompting && !cancelled.running && held.requests == [.camera])
        held.release();await pending.value
        precondition(!cancelled.prompting && !cancelled.running && held.requests == [.camera] && held.maxInFlight == 1)
        precondition(cancelled.message == "You can finish setup whenever you’re ready.")
        await cancelled.begin([.reminders])
        precondition(held.requests == [.camera,.reminders] && !cancelled.running)
        let changed=PermissionFixtureClient(),restricted=IslandPermissionSetup(client:changed)
        changed.waiting=[.camera]
        await restricted.refresh();await restricted.begin([.camera,.notifications])
        changed.values[.camera] = .restricted;await restricted.refresh()
        precondition(!restricted.running && changed.requests == [.camera,.notifications])
        let minimal=IslandPermissionRecommendations.selected(modules:[.home,.shelf,.focus,.notes],snapping:false,hud:false,deviceAlerts:false,healthAlerts:false,player:"nowPlaying",useFocus:false)
        precondition(minimal.isEmpty)
        let snapOnly=IslandPermissionRecommendations.selected(modules:[.home],snapping:true,hud:false,deviceAlerts:false,healthAlerts:false,player:"nowPlaying",useFocus:false)
        precondition(snapOnly == [.accessibility])
        let chosen=IslandPermissionRecommendations.selected(modules:[.day,.tasks,.devices,.mirror],snapping:false,hud:true,deviceAlerts:true,healthAlerts:false,player:"spotify",useFocus:true)
        precondition(chosen == [.calendar,.reminders,.bluetooth,.camera,.accessibility,.input,.notifications,.spotify,.focus])
        precondition(!chosen.contains(.power) && !chosen.contains(.music))
        let music=IslandPermissionRecommendations.selected(modules:[],snapping:false,hud:false,deviceAlerts:false,healthAlerts:true,player:"appleMusic",useFocus:false)
        precondition(music == [.music,.notifications])
        print("PASS: 22 production permission-flow checks; read-only refresh, stable ordering, granted/restricted skips, manual approval/resume, retry, decline, cancellation and no overlapping prompts; no OS permissions requested")
    }
}
