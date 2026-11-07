import AppKit

enum ApplicationRelauncher {
    static func restart() {
        let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
        configuration.arguments=["--relaunch-from-pid",String(ProcessInfo.processInfo.processIdentifier)]
        NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:configuration) { _,error in
            if error == nil { DispatchQueue.main.async { NSApplication.shared.terminate(nil) } }
        }
    }
}
