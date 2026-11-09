import AppKit
@main struct MediaKeysSmoke {
    @MainActor static func main() async {
        func event(_ code:Int,_ state:Int=0xA,_ flags:NSEvent.ModifierFlags=[])->CGEvent {
            NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,subtype:8,data1:(code<<16)|(state<<8),data2:-1)!.cgEvent!
        }
        let tap=IslandMediaKeyTap();var received:[(Int,UInt64,Double)]=[]
        func activate()->Bool { tap.start(authorized:true) { received.append(($0,$1,$2)) } }
        precondition(!tap.start(authorized:false) { _,_,_ in } && tap.fixtureTapStarts == 0)
        precondition(activate() && tap.fixtureTapStarts == 1)
        let volume=event(1)
        precondition(tap.handle(type:volume.type,event:volume) == nil && received.map(\.0) == [1])
        let release=event(1,0xB)
        precondition(tap.handle(type:release.type,event:release) == nil && received.count == 1)
        let option=event(2,0xA,.option)
        precondition(tap.handle(type:option.type,event:option) == nil && received.last?.0 == 2 && received.last?.1 == UInt64(NSEvent.ModifierFlags.option.rawValue))
        let unknown=event(99)
        precondition(tap.handle(type:unknown.type,event:unknown)?.takeUnretainedValue() === unknown && received.count == 2)
        let mouse=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:.zero,mouseButton:.left)!
        precondition(tap.handle(type:mouse.type,event:mouse)?.takeUnretainedValue() === mouse)
        let invalid=event(1,0xC)
        precondition(tap.handle(type:invalid.type,event:invalid)?.takeUnretainedValue() === invalid)
        tap.lastPulse=Date().addingTimeInterval(-7)
        precondition(tap.handle(type:volume.type,event:volume)?.takeUnretainedValue() === volume && tap.send == nil)
        _ = activate();tap.lastPulse=Date().addingTimeInterval(10)
        precondition(tap.handle(type:volume.type,event:volume)?.takeUnretainedValue() === volume && tap.send == nil)
        _ = activate()
        precondition(tap.handle(type:.tapDisabledByUserInput,event:volume)?.takeUnretainedValue() === volume && !activate())
        tap.stop();precondition(activate())
        precondition(tap.handle(type:.tapDisabledByTimeout,event:volume)?.takeUnretainedValue() === volume)
        _ = tap.start(authorized:false) { _,_,_ in };precondition(tap.send == nil && tap.handle(type:volume.type,event:volume)?.takeUnretainedValue() === volume)

        let ui=MediaFixture(),client=XPCHelperClient.shared;Defaults.enabled=true
        await ui.start();precondition(client.starts == 0 && !ui.running)
        client.allowed=true;client.startResult=false;await ui.start();precondition(!ui.running)
        client.startResult=true;await ui.start();ui.receive(code:1,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime);ui.receive(code:99,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime)
        precondition(ui.keys == [1])
        ui.consumesOption=true;ui.receive(code:2,modifiers:UInt64(NSEvent.ModifierFlags.option.rawValue),sentAt:ProcessInfo.processInfo.systemUptime)
        precondition(ui.keys == [1] && ui.optionCalls == 1)
        Defaults.enabled=false;await ui.start();ui.receive(code:1,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime);precondition(!ui.running && ui.keys == [1])
        Defaults.enabled=true;client.allowed=false;await ui.start();precondition(!ui.running)
        client.allowed=true;client.hold=true
        let pending=Task { await ui.start() }
        while client.continuation == nil { await Task.yield() }
        ui.stop();client.continuation?.resume(returning:true);client.continuation=nil;await pending.value
        precondition(!ui.running && client.stops > 0)
        client.hold=false;await ui.start();ui.connectionLost();ui.receive(code:1,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime)
        precondition(!ui.running && ui.keys == [1])
        await ui.start();let startsBeforeHeartbeat=client.starts
        try? await Task.sleep(for:.milliseconds(2200))
        precondition(ui.running && ui.mediaActivity != nil && client.starts > startsBeforeHeartbeat)
        ui.receive(code:1,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime-2)
        precondition(ui.keys == [1])
        ui.receive(code:1,modifiers:0,sentAt:.nan);ui.receive(code:1,modifiers:0,sentAt:ProcessInfo.processInfo.systemUptime+5)
        precondition(ui.keys == [1])
        ui.stop();precondition(ui.mediaActivity == nil)
        print("PASS: 26 production helper/media checks; supported key-only forwarding, key-up suppression, heartbeat expiry, native event pass-through, suspension, UI routing, missing grants, revocation, disconnect, late startup and heartbeat independent of permission polling and stale/future event rejection; in-memory events only, no tap installed or input posted")
    }
}
