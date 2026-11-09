//
//  main.swift
//  IslandControls
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import Security

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    private func connectionRequirement(_ connection:NSXPCConnection,hash:Data) {
        let value=hash.map { String(format:"%02x",$0) }.joined()
        connection.setCodeSigningRequirement("cdhash H\""+value+"\"")
    }
    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        
        // Only this containing Island build may use its unsandboxed controls service.
        let app=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var code:SecStaticCode?;var information:CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL,[],&code) == errSecSuccess,let code,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),nil) == errSecSuccess,
              SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&information) == errSecSuccess,
              let fields=information as? [String:Any],fields[kSecCodeInfoIdentifier as String] as? String == "org.islandapp.Island",
              let hash=fields[kSecCodeInfoUnique as String] as? Data else { NSLog("IslandControls host signature validation failed");return false }
        connectionRequirement(newConnection,hash:hash)
        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: (any IslandControlsProtocol).self)
        
        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = IslandControls()
        newConnection.remoteObjectInterface=NSXPCInterface(with:IslandMediaKeyListener.self)
        exportedObject.mediaListener=newConnection.remoteObjectProxyWithErrorHandler { [weak exportedObject] _ in exportedObject?.stopMediaKeys() } as? IslandMediaKeyListener
        newConnection.invalidationHandler={ [weak exportedObject] in exportedObject?.stopMediaKeys() }
        newConnection.interruptionHandler={ [weak exportedObject] in exportedObject?.stopMediaKeys() }
        newConnection.exportedObject = exportedObject
        
        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()
        
        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
        return true
    }
}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
