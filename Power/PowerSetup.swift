import AppKit
import os

final class PowerSetupDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.activate(ignoringOtherApps:true)
        DispatchQueue.main.async {
            let app=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let log=Logger(subsystem:"org.islandapp.Island",category:"PowerSetup")
            var success=false
            do {
                let prepared=try IslandPowerInstaller.prepare(app:app)
                var error:NSDictionary?;let script=NSAppleScript(source:prepared.appleScript)
                let result=script?.executeAndReturnError(&error)
                success=result != nil && error == nil
                if let error { let code=(error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0;log.error("Power setup returned code \(code,privacy:.public)") }
            } catch { log.error("Power setup preparation failed code \((error as NSError).code,privacy:.public)") }
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.islandapp.Island.PowerSetupFinished"),object:success ? "ok" : "failed",userInfo:nil,deliverImmediately:true)
            NSApp.terminate(nil)
        }
    }
}
@main struct PowerSetupMain {
    static func main() {
        let app=NSApplication.shared;let delegate=PowerSetupDelegate();app.delegate=delegate;app.setActivationPolicy(.accessory);withExtendedLifetime(delegate) { app.run() }
    }
}
