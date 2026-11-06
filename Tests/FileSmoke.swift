import Foundation
@main struct FileSmoke {
 static func main() throws {
  let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  for path in ["../file","/absolute","folder/../../escape","C:\\escape","dir/../name"] { precondition(!IslandFileCommands.safeArchiveEntry(path)) }
  precondition(IslandFileCommands.safeArchiveEntry("folder/file.txt"))
  let output = root.appendingPathComponent("safe-output")
  try IslandFileCommands.unzip(root.appendingPathComponent("safe.zip"),to:output)
  let contents = try String(contentsOf:output.appendingPathComponent("folder/hello.txt"),encoding:.utf8)
  precondition(contents == "Hello Island")
  for fixture in ["traversal","symlink"] {
   var rejected = false
   do { try IslandFileCommands.unzip(root.appendingPathComponent(fixture+".zip"),to:root.appendingPathComponent(fixture+"-output")) } catch { rejected = true }
   precondition(rejected)
  }
  precondition(!FileManager.default.fileExists(atPath:root.appendingPathComponent("escape.txt").path))
  print("PASS: 10 archive path, extraction and symlink checks")
 }
}
