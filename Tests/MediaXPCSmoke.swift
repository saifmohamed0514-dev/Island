import AppKit
// An anonymous in-process listener exercises real NSXPC serialization and both
// production interfaces. Only AX authorization/native tap creation are fixtures.
final class MediaWireDelegate:NSObject,NSXPCListenerDelegate {
    let server=IslandControls()
    var accepted:NSXPCConnection?
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection connection:NSXPCConnection)->Bool {
        connection.exportedInterface=NSXPCInterface(with:IslandControlsProtocol.self)
        connection.remoteObjectInterface=NSXPCInterface(with:IslandMediaKeyListener.self)
        connection.exportedObject=server
        server.mediaListener=connection.remoteObjectProxyWithErrorHandler { _ in } as? IslandMediaKeyListener
        connection.resume();accepted=connection;return true
    }
}
final class MediaWireSink:NSObject,IslandMediaKeyListener {
    private let lock=NSLock()
    private var entries:[(Int,UInt64,Double)]=[]
    func mediaKey(_ code:Int,modifiers:UInt64,sentAt:Double) { lock.lock();entries.append((code,modifiers,sentAt));lock.unlock() }
    func values()->[(Int,UInt64,Double)] { lock.lock();defer { lock.unlock() };return entries }
}
@main struct MediaXPCSmoke {
    @MainActor static func main() async {
        DispatchQueue.global().asyncAfter(deadline:.now()+10) { fputs("FAIL: XPC fixture timed out\n",stderr);exit(1) }
        let listener=NSXPCListener.anonymous(),delegate=MediaWireDelegate(),sink=MediaWireSink()
        listener.delegate=delegate;listener.resume()
        let connection=NSXPCConnection(listenerEndpoint:listener.endpoint)
        connection.remoteObjectInterface=NSXPCInterface(with:IslandControlsProtocol.self)
        connection.exportedInterface=NSXPCInterface(with:IslandMediaKeyListener.self);connection.exportedObject=sink;connection.resume()
        let proxy=connection.remoteObjectProxyWithErrorHandler { error in fputs("FAIL: XPC \(error.localizedDescription)\n",stderr);exit(1) } as! IslandControlsProtocol
        let began:Bool=await withCheckedContinuation { continuation in proxy.startMediaKeys { continuation.resume(returning:$0) } }
        precondition(began)
        let event=NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:.option,timestamp:0,windowNumber:0,context:nil,subtype:8,data1:(2<<16)|(0xA<<8),data2:-1)!.cgEvent!
        precondition(delegate.server.mediaTap.handle(type:event.type,event:event) == nil)
        while sink.values().isEmpty { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(sink.values().first?.0 == 2 && sink.values().first?.1 == UInt64(NSEvent.ModifierFlags.option.rawValue) && ProcessInfo.processInfo.systemUptime-(sink.values().first?.2 ?? 0) <= 1)
        proxy.stopMediaKeys()
        while delegate.server.mediaTap.send != nil { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(delegate.server.mediaTap.send == nil)
        connection.invalidate();delegate.accepted?.invalidate();listener.invalidate()
        print("PASS: 4 real anonymous-XPC media checks; start acknowledgement, production event filtering, typed key/modifier callback and stop delivery; no privacy request, global tap or posted input; caller attestation remains a separate installed-service boundary")
    }
}
