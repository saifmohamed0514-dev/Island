//
//  IslandControls.swift
//  IslandControls
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import AppKit
import ApplicationServices
import IOKit
import CoreGraphics

class IslandControls: NSObject, IslandControlsProtocol {
    var mediaListener:IslandMediaKeyListener?
    private let mediaTap=IslandMediaKeyTap()
    deinit { DispatchQueue.main.async { [mediaTap] in mediaTap.stop() } }
    @objc func startMediaKeys(with reply:@escaping(Bool)->Void) {
        DispatchQueue.main.async { [self] in
            guard let mediaListener else { reply(false);return }
            reply(mediaTap.start(authorized:accessibilityAllowed()) { [weak mediaListener] code,flags,time in mediaListener?.mediaKey(code,modifiers:flags,sentAt:time) })
        }
    }
    @objc func stopMediaKeys() { DispatchQueue.main.async { [self] in mediaTap.stop() } }

    // A real, read-only AX operation detects grants/revocations even when the
    // process-trust flag has not caught up after the Settings switch changes.
    private func accessibilityAllowed()->Bool {
        let system=AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system,0.2)
        var focused:CFTypeRef?
        let result=AXUIElementCopyAttributeValue(system,kAXFocusedApplicationAttribute as CFString,&focused)
        if result == .success { return true }
        if result == .apiDisabled { return false }
        return AXIsProcessTrusted()
    }

    // Hold the actual clicked window throughout a drag, even if focus changes.
    private var snapWindows:[String:AXUIElement]=[:]
    private let snapLock=NSLock()
    private func attribute(_ element:AXUIElement,_ name:String)->CFTypeRef? {
        var result:CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,name as CFString,&result) == .success else { return nil }
        return result
    }
    private func elementAttribute(_ element:AXUIElement,_ name:String)->AXUIElement? {
        guard let value=attribute(element,name),CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func windowRect(_ window:AXUIElement)->CGRect? {
        AXUIElementSetMessagingTimeout(window,0.3)
        guard let p=attribute(window,kAXPositionAttribute),let s=attribute(window,kAXSizeAttribute),CFGetTypeID(p) == AXValueGetTypeID(),CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),[point.x,point.y,size.width,size.height].allSatisfy({ $0.isFinite }),size.width>0,size.height>0 else { return nil }
        return CGRect(origin:point,size:size)
    }
    private func numbers(_ rect:CGRect?)->[NSNumber]? { rect.map { [$0.minX,$0.minY,$0.width,$0.height].map { NSNumber(value:Double($0)) } } }
    private func mainWindow(_ pid:Int32)->AXUIElement? {
        guard accessibilityAllowed(),pid>0 else { return nil }
        let app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.3)
        return elementAttribute(app,kAXFocusedWindowAttribute) ?? elementAttribute(app,kAXMainWindowAttribute)
    }
    @objc func windowBounds(_ pid:Int32,with reply:@escaping([NSNumber]?)->Void) { reply(mainWindow(pid).flatMap { numbers(windowRect($0)) }) }
    @objc func captureSnapWindow(_ x:Double,y:Double,with reply:@escaping(String?,Int32,[NSNumber]?)->Void) {
        guard accessibilityAllowed(),x.isFinite,y.isFinite,abs(x)<100000,abs(y)<100000 else { reply(nil,0,nil);return }
        let system=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(system,0.3)
        var hit:AXUIElement?
        guard AXUIElementCopyElementAtPosition(system,Float(x),Float(y),&hit) == .success,let hit else { reply(nil,0,nil);return }
        let window=(attribute(hit,kAXRoleAttribute) as? String == kAXWindowRole) ? hit : elementAttribute(hit,kAXWindowAttribute)
        guard let window,attribute(window,"AXFullScreen") as? Bool != true,attribute(window,kAXMinimizedAttribute) as? Bool != true,let rect=windowRect(window) else { reply(nil,0,nil);return }
        var pid:pid_t=0
        guard AXUIElementGetPid(window,&pid) == .success,pid>0 else { reply(nil,0,nil);return }
        let token=UUID().uuidString
        snapLock.lock();if snapWindows.count>=16 { snapWindows.removeAll() };snapWindows[token]=window;snapLock.unlock()
        reply(token,pid,numbers(rect))
    }
    private func snapWindow(_ token:String)->AXUIElement? { snapLock.lock();defer { snapLock.unlock() };return snapWindows[token] }
    @objc func snapWindowBounds(_ token:String,with reply:@escaping([NSNumber]?)->Void) {
        guard accessibilityAllowed(),let window=snapWindow(token) else { reply(nil);return };reply(numbers(windowRect(window)))
    }
    @objc func releaseSnapWindow(_ token:String) { snapLock.lock();snapWindows.removeValue(forKey:token);snapLock.unlock() }
    private func tile(_ window:AXUIElement,x:Double,y:Double,width:Double,height:Double)->Bool {
        guard accessibilityAllowed(),[x,y,width,height].allSatisfy({ $0.isFinite && abs($0)<100000 }),width>100,height>100,attribute(window,"AXFullScreen") as? Bool != true else { return false }
        AXUIElementSetMessagingTimeout(window,0.5)
        var size=CGSize(width:width,height:height),point=CGPoint(x:x,y:y)
        guard let sizeValue=AXValueCreate(.cgSize,&size),let pointValue=AXValueCreate(.cgPoint,&point) else { return false }
        // Move before growing, then size and position again: AppKit can clamp a
        // requested size to the old display while a window crosses displays.
        _ = AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,pointValue)
        let resized=AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,sizeValue)
        let moved=AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,pointValue)
        return resized == .success && moved == .success
    }
    @objc func tileSnapWindow(_ token:String,x:Double,y:Double,width:Double,height:Double,with reply:@escaping(Bool)->Void) {
        guard let window=snapWindow(token) else { reply(false);return };reply(tile(window,x:x,y:y,width:width,height:height))
    }
    @objc func tileWindow(_ pid:Int32,x:Double,y:Double,width:Double,height:Double,with reply:@escaping(Bool)->Void) {
        guard let window=mainWindow(pid) else { reply(false);return };reply(tile(window,x:x,y:y,width:width,height:height))
    }

    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(accessibilityAllowed())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if accessibilityAllowed() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(self.accessibilityAllowed())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}


// Owns only the supported media-key events. Ordinary typing is never forwarded.
// The service already owns AX window access; the sandboxed UI receives just the
// key code/modifiers over its authenticated, local XPC connection.
final class IslandMediaKeyTap {
    deinit { stop() }
    private let lock=NSLock()
    private var eventRunLoop:CFRunLoop?
    private var port:CFMachPort?
    private var retainedContext:Unmanaged<IslandMediaKeyTap>?
    private var source:CFRunLoopSource?
    private var send:((Int,UInt64,Double)->Void)?
    private var suspended=false
    private var lastPulse=Date.distantPast
    func start(authorized:Bool,send:@escaping(Int,UInt64,Double)->Void)->Bool {
        guard authorized else { stop();return false }
        lock.lock()
        guard !suspended else { lock.unlock();return false }
        if let port,CFMachPortIsValid(port) {
            self.send=send;lastPulse=Date()
            let enabled=CGEvent.tapIsEnabled(tap:port);lock.unlock();return enabled
        }
        lock.unlock();stop()
        lock.lock();defer { lock.unlock() }
        self.send=send;lastPulse=Date()
        let mask=CGEventMask(1 << CGEventType(rawValue:14)!.rawValue)
        let context=Unmanaged.passRetained(self)
        guard let created=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner=Unmanaged<IslandMediaKeyTap>.fromOpaque(context).takeUnretainedValue()
            return owner.handle(type:type,event:event)
        },userInfo:context.toOpaque()) else { context.release();self.send=nil;return false }
        guard let madeSource=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,created,0) else {
            CFMachPortInvalidate(created);context.release();self.send=nil;return false
        }
        retainedContext=context;port=created;source=madeSource
        // XPC services need not drive the main CF run loop. Give the tap its own
        // run loop so native events are serviced even while XPC work is busy.
        let thread=Thread { [self] in
            let runLoop=CFRunLoopGetCurrent()
            lock.lock()
            guard port === created,CFMachPortIsValid(created) else { lock.unlock();return }
            eventRunLoop=runLoop
            CFRunLoopAddSource(runLoop,madeSource,.commonModes)
            lock.unlock()
            CFRunLoopRun()
        }
        thread.name="Island Media Keys";thread.qualityOfService = .userInteractive;thread.start()
        CGEvent.tapEnable(tap:created,enable:true)
        return CGEvent.tapIsEnabled(tap:created)
    }
    func stop() {
        lock.lock()
        let oldPort=port,oldSource=source,oldLoop=eventRunLoop,context=retainedContext
        port=nil;source=nil;eventRunLoop=nil;send=nil;suspended=false;lastPulse = .distantPast;retainedContext=nil
        lock.unlock()
        if let oldPort { CGEvent.tapEnable(tap:oldPort,enable:false);CFMachPortInvalidate(oldPort) }
        if let oldSource,let oldLoop { CFRunLoopRemoveSource(oldLoop,oldSource,.commonModes);CFRunLoopStop(oldLoop);CFRunLoopWakeUp(oldLoop) }
        context?.release()
    }
    private func handle(type:CGEventType,event:CGEvent)->Unmanaged<CGEvent>? {
        // If the UI stops servicing its connection, stop filtering and leave the
        // media keys to macOS rather than consuming them without a response.
        lock.lock()
        let elapsed=Date().timeIntervalSince(lastPulse)
        guard elapsed >= 0,elapsed <= 6 else { lock.unlock();stop();return Unmanaged.passUnretained(event) }
        defer { lock.unlock() }
        if type == .tapDisabledByTimeout { if let port { CGEvent.tapEnable(tap:port,enable:true) };return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByUserInput { suspended=true;return Unmanaged.passUnretained(event) }
        guard type.rawValue == 14,let native=NSEvent(cgEvent:event),native.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let code=(native.data1 & 0xFFFF0000)>>16,state=(native.data1 & 0xFF00)>>8
        guard [0,1,2,3,7,21,22].contains(code),state == 0xA || state == 0xB else { return Unmanaged.passUnretained(event) }
        if state == 0xA { send?(code,UInt64(native.modifierFlags.rawValue),ProcessInfo.processInfo.systemUptime) }
        return nil
    }
}
