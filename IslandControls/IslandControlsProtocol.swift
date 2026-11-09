//
//  IslandControlsProtocol.swift
//  IslandControls
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol IslandMediaKeyListener {
    func mediaKey(_ code:Int,modifiers:UInt64,sentAt:Double)
}

@objc protocol IslandControlsProtocol {
    func startMediaKeys(with reply:@escaping(Bool)->Void)
    func stopMediaKeys()
    func captureSnapWindow(_ x:Double,y:Double,with reply:@escaping(String?,Int32,[NSNumber]?)->Void)
    func snapWindowBounds(_ token:String,with reply:@escaping([NSNumber]?)->Void)
    func tileSnapWindow(_ token:String,x:Double,y:Double,width:Double,height:Double,with reply:@escaping(Bool)->Void)
    func releaseSnapWindow(_ token:String)
    func windowBounds(_ pid:Int32,with reply:@escaping([NSNumber]?)->Void)
    func tileWindow(_ pid: Int32, x: Double, y: Double, width: Double, height: Double, with reply: @escaping (Bool) -> Void)
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "org.islandapp.Island.BoringNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any IslandControlsProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? IslandControlsProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/
