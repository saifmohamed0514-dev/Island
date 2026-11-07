import Foundation
import Security
import CryptoKit
import os

enum IslandPowerInstaller {
    struct Script {
        let shell:String
        var appleScript:String {
            let quoted="\""+shell.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n")+"\""
            return "do shell script "+quoted+" with administrator privileges"
        }
    }
    static func prepare(app:URL) throws -> Script {
        let executable=app.appendingPathComponent("Contents/Resources/IslandPower")
        var code:SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL,[],&code) == errSecSuccess,let code,SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),nil) == errSecSuccess else { throw CocoaError(.executableNotLoadable) }
        var information:CFDictionary?
        guard SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&information) == errSecSuccess,let fields=information as? [String:Any],fields[kSecCodeInfoIdentifier as String] as? String == "org.islandapp.Island",let hash=fields[kSecCodeInfoUnique as String] as? Data,let binary=try? Data(contentsOf:executable) else { throw CocoaError(.fileReadCorruptFile) }
        let clientHash=hash.map { String(format:"%02x",$0) }.joined(),digest=SHA256.hash(data:binary).map { String(format:"%02x",$0) }.joined()
        let team=fields[kSecCodeInfoTeamIdentifier as String] as? String
        let signedTeam=team.flatMap { value in value.count == 10 && value.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) ? value : nil }
        let identity=signedTeam.map { ["--team-id",$0] } ?? ["--client-hash",clientHash]
        let plist:[String:Any]=["Label":"org.islandapp.Island.Power","ProgramArguments":["/Library/PrivilegedHelperTools/org.islandapp.Island.Power"]+identity,"MachServices":["org.islandapp.Island.Power":true]]
        guard let data=try? PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0) else { throw CocoaError(.propertyListWriteInvalid) }
        func quote(_ text:String)->String { "'"+text.replacingOccurrences(of:"'",with:"'\"'\"'")+"'" }
        let script="""
        set -eu
        /bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
        stage=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.island-power.XXXXXX)
        trap '/bin/rm -rf "$stage"' EXIT
        /usr/bin/ditto --norsrc --noextattr \(quote(executable.path)) "$stage/IslandPower"
        actual=$(/usr/bin/shasum -a 256 "$stage/IslandPower" | /usr/bin/awk '{print $1}')
        test "$actual" = \(quote(digest))
        /usr/bin/printf '%s' \(quote(data.base64EncodedString())) | /usr/bin/base64 -D > "$stage/service.plist"
        /usr/bin/codesign --verify --strict "$stage/IslandPower"
        /bin/launchctl bootout system/org.islandapp.Island.Power 2>/dev/null || true
        /usr/bin/install -o root -g wheel -m 755 "$stage/IslandPower" /Library/PrivilegedHelperTools/org.islandapp.Island.Power
        /usr/bin/install -o root -g wheel -m 644 "$stage/service.plist" /Library/LaunchDaemons/org.islandapp.Island.Power.plist
        /bin/launchctl bootstrap system /Library/LaunchDaemons/org.islandapp.Island.Power.plist
        """
        return Script(shell:script)
    }
}
