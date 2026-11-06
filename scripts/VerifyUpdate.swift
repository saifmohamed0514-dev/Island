import Foundation
import CryptoKit
let args = CommandLine.arguments
if args.count != 4 { fputs("Expected archive, public key and signature.\n", stderr); exit(2) }
do {
    guard let publicBytes = Data(base64Encoded: args[2]), let signature = Data(base64Encoded: args[3]) else { exit(2) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    guard key.isValidSignature(signature, for: data) else { fputs("Archive signature does not match the app’s public key.\n", stderr); exit(1) }
} catch { fputs("Could not verify update signature.\n", stderr); exit(1) }
