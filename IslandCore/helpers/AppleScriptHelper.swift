//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    @discardableResult
    class func execute(_ scriptText: String,permissionTarget:String,userInitiated:Bool=false) async throws -> NSAppleEventDescriptor? {
        guard await IslandSystemPermissionClient.automationStatus(permissionTarget) == .allowed else {
            if userInitiated {
                await MainActor.run { IslandSettingsController.shared.showPermissions(permissionTarget == "com.spotify.client" ? .spotify : .music) }
            }
            throw NSError(domain:"IslandPermission",code:1,userInfo:[NSLocalizedDescriptionKey:"Set up player access in Island’s Permissions page."])
        }
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String,permissionTarget:String) async throws {
        _ = try await execute(scriptText,permissionTarget:permissionTarget,userInitiated:true)
    }
}
