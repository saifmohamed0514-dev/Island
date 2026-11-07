// Narrow, root-owned service. Its only privileged operation is setting Low Power Mode.
import Foundation

@objc(IslandPowerControl) protocol IslandPowerControl {
    func ping(with reply:@escaping(Bool)->Void)
    func setLowPowerMode(_ enabled:Bool,onACPower:Bool,with reply:@escaping(Bool)->Void)
}
enum IslandPowerRules {
    static func arguments(enabled:Bool,onACPower:Bool)->[String] { [onACPower ? "-c" : "-b","lowpowermode",enabled ? "1" : "0"] }
    static func validHash(_ value:String)->Bool { [40,64].contains(value.count) && value.allSatisfy { $0.isHexDigit && $0.isASCII } }
}
final class IslandPowerService:NSObject,IslandPowerControl {
    private let commands=DispatchQueue(label:"Island.Power.Commands")
    func ping(with reply:@escaping(Bool)->Void) { reply(geteuid() == 0) }
    func setLowPowerMode(_ enabled:Bool,onACPower:Bool,with reply:@escaping(Bool)->Void) {
        commands.async {
            guard geteuid() == 0 else { reply(false);return }
            let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/pmset");process.arguments=IslandPowerRules.arguments(enabled:enabled,onACPower:onACPower)
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            do { try process.run();process.waitUntilExit();reply(process.terminationStatus == 0) } catch { reply(false) }
        }
    }
}
final class PowerDelegate:NSObject,NSXPCListenerDelegate {
    let requirement:String
    init(requirement:String) { self.requirement=requirement }
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection connection:NSXPCConnection)->Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface=NSXPCInterface(with:IslandPowerControl.self)
        connection.exportedObject=IslandPowerService();connection.resume();return true
    }
}
guard CommandLine.arguments.count == 3,geteuid() == 0 else { exit(1) }
let value=CommandLine.arguments[2],requirement:String
if CommandLine.arguments[1] == "--client-hash",IslandPowerRules.validHash(value) { requirement="cdhash H\"\(value)\"" }
else if CommandLine.arguments[1] == "--team-id",value.count == 10,value.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) { requirement="identifier \"org.islandapp.Island\" and anchor apple generic and certificate leaf[subject.OU] = \""+value+"\"" }
else { exit(1) }
let delegate=PowerDelegate(requirement:requirement)
let listener=NSXPCListener(machServiceName:"org.islandapp.Island.Power");listener.delegate=delegate;listener.resume();dispatchMain()
