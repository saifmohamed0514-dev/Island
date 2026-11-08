import AppKit
@main struct MediaKeysSmoke {
    @MainActor static func main() {
        let fixture=MediaFixture(),empty=CGEvent(source:nil)!
        func event(_ code:Int,_ state:Int=0xA,_ flags:NSEvent.ModifierFlags=[])->CGEvent {
            NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,subtype:8,data1:(code<<16)|(state<<8),data2:-1)!.cgEvent!
        }
        precondition(fixture.handleEvent(type:.null,event:empty)?.takeUnretainedValue() === empty)
        precondition(fixture.handleEvent(type:.tapDisabledByUserInput,event:empty)?.takeUnretainedValue() === empty && fixture.suspendedByUser)
        let up=event(0,0xB)
        precondition(fixture.handleEvent(type:up.type,event:up)?.takeUnretainedValue() === up && fixture.keys.isEmpty)
        let volume=event(1)
        precondition(fixture.handleEvent(type:volume.type,event:volume) == nil && fixture.keys == [1])
        fixture.consumesOption=true
        let option=event(2,0xA,.option)
        precondition(fixture.handleEvent(type:option.type,event:option) == nil && fixture.optionCalls == 1 && fixture.keys == [1])
        let unknown=event(99)
        precondition(fixture.handleEvent(type:unknown.type,event:unknown)?.takeUnretainedValue() === unknown)
        let mouse=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:.zero,mouseButton:.left)!
        precondition(fixture.handleEvent(type:mouse.type,event:mouse)?.takeUnretainedValue() === mouse)
        precondition(fixture.handleEvent(type:.tapDisabledByTimeout,event:empty)?.takeUnretainedValue() === empty && fixture.keys == [1])
        print("PASS: 8 production media-key handler checks; callback suspension/timeout types, unrelated events, key-up, supported keys and Option routing; events allocated in memory only, no input posted")
    }
}
