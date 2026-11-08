import Foundation
@MainActor final class PermissionFixtureClient:IslandPermissionClient {
    var values=Dictionary(uniqueKeysWithValues:IslandPermission.allCases.map { ($0,IslandPermissionStatus.ask) })
    var requests:[IslandPermission]=[]
    var fullReads=0,controlReads=0
    var waiting:Set<IslandPermission>=[]
    var nativeWaiting:Set<IslandPermission>=[]
    var declining:Set<IslandPermission>=[]
    var unconfirmed:Set<IslandPermission>=[]
    var checking:Set<IslandPermission>=[]
    var holdNextSnapshot=false
    var holdSnapshotAfterRequest=false
    var snapshotContinuation:CheckedContinuation<Void,Never>?
    var hold:IslandPermission?
    var continuation:CheckedContinuation<Void,Never>?
    var inFlight=0,maxInFlight=0
    func snapshot() async -> [IslandPermission:IslandPermissionStatus] {
        fullReads+=1
        let captured=values
        if holdNextSnapshot { holdNextSnapshot=false;await withCheckedContinuation { snapshotContinuation=$0 } }
        return captured
    }
    func controlsSnapshot() async -> [IslandPermission:IslandPermissionStatus] { controlReads+=1;return values.filter { $0.key == .accessibility || $0.key == .input || $0.key == .mediaControls } }
    func releaseSnapshot() { snapshotContinuation?.resume();snapshotContinuation=nil }
    func request(_ key:IslandPermission) async -> IslandPermissionAttempt {
        requests.append(key);inFlight+=1;maxInFlight=max(maxInFlight,inFlight);defer { inFlight-=1 }
        if hold == key { await withCheckedContinuation { continuation=$0 } }
        if waiting.contains(key) { return .waitingInSettings }
        if nativeWaiting.contains(key) { return .waitingForApproval }
        values[key] = checking.contains(key) ? .checking : unconfirmed.contains(key) ? .ask : declining.contains(key) ? .settings : .allowed
        if holdSnapshotAfterRequest { holdSnapshotAfterRequest=false;holdNextSnapshot=true }
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
        precondition(chosen == [.calendar,.reminders,.bluetooth,.camera,.accessibility,.mediaControls,.notifications,.spotify,.focus])
        precondition(!chosen.contains(.power) && !chosen.contains(.music))
        let music=IslandPermissionRecommendations.selected(modules:[],snapping:false,hud:false,deviceAlerts:false,healthAlerts:true,player:"appleMusic",useFocus:false)
        precondition(music == [.music,.notifications])
        let inactiveClient=PermissionFixtureClient(),inactive=IslandPermissionSetup(client:inactiveClient)
        inactiveClient.waiting=[.accessibility]
        await inactive.refresh();await inactive.begin([.accessibility,.calendar])
        precondition(inactive.waitingInSettings)
        inactiveClient.values[.accessibility] = .allowed
        await inactive.refresh(mayContinue:false)
        precondition(inactive.running && inactive.current == .accessibility && inactiveClient.requests == [.accessibility])
        await inactive.refresh(mayContinue:true)
        precondition(!inactive.running && inactiveClient.requests == [.accessibility,.calendar])
        precondition(IslandPermission.allCases.allSatisfy { !$0.approvalHelp.isEmpty })
        let nativeClient=PermissionFixtureClient(),native=IslandPermissionSetup(client:nativeClient)
        nativeClient.nativeWaiting=[.input]
        await native.refresh();await native.begin([.input,.camera])
        precondition(native.waiting && !native.waitingInSettings && native.current == .input)
        await native.refresh();precondition(nativeClient.requests == [.input])
        nativeClient.values[.input] = .allowed;await native.refresh()
        precondition(!native.running && nativeClient.requests == [.input,.camera])
        // A completed native API with a delayed OS grant must remain visible.
        let lagClient=PermissionFixtureClient(),lag=IslandPermissionSetup(client:lagClient)
        lagClient.unconfirmed=[.input]
        await lag.refresh();await lag.begin([.input,.camera])
        precondition(lag.running && lag.waiting && lag.current == .input && lagClient.requests == [.input])
        lagClient.values[.input] = .allowed;await lag.refresh()
        precondition(!lag.running && lagClient.requests == [.input,.camera])

        let unknownClient=PermissionFixtureClient(),unknown=IslandPermissionSetup(client:unknownClient)
        unknownClient.checking=[.accessibility]
        await unknown.refresh();await unknown.begin([.accessibility,.camera])
        precondition(unknown.running && unknown.waiting && unknown.current == .accessibility)
        unknownClient.values[.accessibility] = .allowed;await unknown.refresh()
        precondition(!unknown.running && unknownClient.requests == [.accessibility,.camera])

        // A poll captured before approval must not overwrite the new grant.
        let staleClient=PermissionFixtureClient(),stale=IslandPermissionSetup(client:staleClient)
        staleClient.hold = .camera;await stale.refresh()
        let approval=Task { await stale.begin([.camera]) }
        while staleClient.continuation == nil { await Task.yield() }
        staleClient.holdNextSnapshot=true
        let oldPoll=Task { await stale.refresh() }
        while staleClient.snapshotContinuation == nil { await Task.yield() }
        staleClient.release();await approval.value
        precondition(stale.status(.camera) == .allowed)
        staleClient.releaseSnapshot();await oldPoll.value
        precondition(stale.status(.camera) == .allowed && !stale.running)

        // Returning from Settings while a poll is underway forces a fresh read.
        let coalescedClient=PermissionFixtureClient(),coalesced=IslandPermissionSetup(client:coalescedClient)
        await coalesced.refresh();coalescedClient.holdNextSnapshot=true
        let firstPoll=Task { await coalesced.refresh() }
        while coalescedClient.snapshotContinuation == nil { await Task.yield() }
        coalescedClient.values[.input] = .allowed;await coalesced.refresh()
        coalescedClient.releaseSnapshot();await firstPoll.value
        precondition(coalesced.status(.input) == .allowed && !coalesced.refreshing)

        // Keep prompt ownership until the post-request status check finishes.
        let confirmClient=PermissionFixtureClient(),confirm=IslandPermissionSetup(client:confirmClient)
        await confirm.refresh();confirmClient.holdSnapshotAfterRequest=true
        let confirmation=Task { await confirm.begin([.camera]) }
        while confirmClient.snapshotContinuation == nil { await Task.yield() }
        precondition(confirm.prompting)
        await confirm.begin([.notifications]);await confirm.skip()
        precondition(confirmClient.requests == [.camera])
        confirmClient.releaseSnapshot();await confirmation.value
        precondition(!confirm.prompting && !confirm.running)

        var foreground=false
        let backgroundClient=PermissionFixtureClient(),background=IslandPermissionSetup(client:backgroundClient,canPresentNext:{ foreground })
        await background.refresh();await background.begin([.camera,.notifications])
        precondition(background.waiting && background.current == .camera && background.status(.camera) == .allowed && backgroundClient.requests == [.camera])
        foreground=true;await background.refresh()
        precondition(!background.running && backgroundClient.requests == [.camera,.notifications])
        background.selected=[.camera,.notifications];precondition(background.readyCount == 2)
        backgroundClient.values[.camera] = .settings;await background.refresh()
        precondition(background.readyCount == 1 && backgroundClient.requests == [.camera,.notifications])
        precondition(background.message.contains("Some features still need access"))
        let lightClient=PermissionFixtureClient(),light=IslandPermissionSetup(client:lightClient)
        lightClient.values[.camera] = .allowed;await light.refresh()
        lightClient.values[.input] = .allowed;await light.refresh(controlsOnly:true)
        precondition(light.status(.camera) == .allowed && light.status(.input) == .allowed)
        precondition(lightClient.fullReads == 1 && lightClient.controlReads == 1)
        precondition(lightClient.requests.isEmpty)
        lightClient.values[.mediaControls] = .allowed;lightClient.values[.input] = .settings;await light.refresh(controlsOnly:true)
        precondition(light.status(.mediaControls) == .allowed && light.status(.input) == .settings)
        precondition(light.status(.accessibility) == .ask)
        let approved=IslandControlAccess(window:true,media:true).statuses
        precondition(approved[.accessibility] == .allowed)
        precondition(approved[.mediaControls] == .allowed && approved[.input] == .allowed)
        let windowOnly=IslandControlAccess(window:true,media:false).statuses
        precondition(windowOnly[.accessibility] == .allowed && windowOnly[.mediaControls] == .ask)
        let mediaOnly=IslandControlAccess(window:false,media:true).statuses
        precondition(mediaOnly[.accessibility] == .ask && mediaOnly[.mediaControls] == .allowed)
        let unavailableHelper=IslandControlAccess(window:nil,media:true).statuses
        precondition(unavailableHelper[.accessibility] == .checking && unavailableHelper[.mediaControls] == .allowed)
        precondition(!IslandPermission.visibleCases.contains(.input))
        precondition(IslandPermission.visibleCases.contains(.mediaControls))
        precondition(chosen.contains(.mediaControls) && !chosen.contains(.input))
        PermissionProbeFixture.checkBoth()
        print("PASS: 65 production permission-flow and app/helper access-probe checks; delayed grants, stale polls, refresh coalescing, foreground resume, revocation, request serialization and cancellation; no OS permissions requested")
    }
}
