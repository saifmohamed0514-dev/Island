import Foundation
import ApplicationServices
// Only the OS boundary is substituted. Both probe methods come directly from
// the production app/helper files, including their real error handling.
enum PermissionProbeFixture {
    static var result:AXError = .success
    static var trusted=false
    static func makeSystem()->Int { 0 }
    static func setTimeout(_ system:Int,_ timeout:Float) {}
    static func read(_ system:Int,_ attribute:CFString,_ output:inout CFTypeRef?)->AXError { result }
    static func trustedValue()->Bool { trusted }
    static func checkBoth() {
        trusted=false;precondition(!MainAccessProbe.check())
        trusted=true;precondition(MainAccessProbe.check())
        for check in [HelperAccessProbe.check] {
            trusted=false;result = .success;precondition(check())
            trusted=true;result = .apiDisabled;precondition(!check())
            trusted=false;result = .apiDisabled;precondition(!check())
            trusted=true;result = .cannotComplete;precondition(check())
            trusted=false;result = .cannotComplete;precondition(!check())
            trusted=false;result = .noValue;precondition(!check())
        }
    }
}
