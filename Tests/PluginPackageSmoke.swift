import Foundation
@main struct PluginPackageSmoke {
 static func main() throws {
  let parent=FileManager.default.temporaryDirectory.appendingPathComponent("island-package-tests-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
  defer { try? FileManager.default.removeItem(at:parent) }
  let binary=parent.appendingPathComponent("fixture");try Data("fixture executable only".utf8).write(to:binary)
  let root=parent.appendingPathComponent("Island Plugins",isDirectory:true)
  try IslandPluginPackage.write(to:root,executable:binary,version:"2.10.0")
  var count=0
  func check(_ condition:Bool) { precondition(condition);count+=1 }
  for name in ["ChatGPT","Claude"] {
   let folder=root.appendingPathComponent("Island for "+name),config=folder.appendingPathComponent(".mcp.json")
   let json=try JSONSerialization.jsonObject(with:Data(contentsOf:config)) as! [String:Any],servers=json["mcpServers"] as! [String:[String:Any]],server=servers["island"]!
   check(server["command"] as? String == binary.path)
   check((server["args"] as? [String])?.contains(root.appendingPathComponent("Local data").path) == true)
   check(try Data(contentsOf:folder.appendingPathComponent("bin/IslandPlugin")) == Data(contentsOf:binary))
   let files=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:nil)!.allObjects as! [URL]
   check(!files.contains { $0.path.lowercased().contains("hooks") })
   let skill=try String(contentsOf:folder.appendingPathComponent("skills/island/SKILL.md"),encoding:.utf8);check(skill.contains("ask_question") && skill.contains("report_progress"));check(skill.contains(binary.path) && skill.contains("--call TOOL") && !skill.contains("\\(quote"))
   let portable=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("mcp.json"))) as! [String:Any];check(portable["$schema"] != nil)
  }
  let bundle=root.appendingPathComponent("Island for Claude.mcpb")
  check(FileManager.default.fileExists(atPath:bundle.path))
  let unpacked=parent.appendingPathComponent("Unpacked");let unpack=Process();unpack.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");unpack.arguments=["-x","-k",bundle.path,unpacked.path];try unpack.run();unpack.waitUntilExit();check(unpack.terminationStatus==0)
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:unpacked.appendingPathComponent("manifest.json"))) as! [String:Any];check(manifest["manifest_version"] as? String=="0.3");check(((manifest["server"] as? [String:Any])?["mcp_config"] as? [String:Any])?["command"] as? String == binary.path)
  check(FileManager.default.fileExists(atPath:unpacked.appendingPathComponent("bin/IslandPlugin").path))
  let marketplace=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent(".agents/plugins/marketplace.json"))) as! [String:Any];check(marketplace["name"] as? String=="island-local")
  try IslandPluginPackage.write(to:root,executable:binary,version:"2.10.1");check(FileManager.default.fileExists(atPath:root.appendingPathComponent("START HERE.txt").path))
  let foreign=parent.appendingPathComponent("Foreign");try FileManager.default.createDirectory(at:foreign,withIntermediateDirectories:false)
  do { try IslandPluginPackage.write(to:foreign,executable:binary,version:"2.10.0");preconditionFailure("Overwrote an unrelated folder") } catch { check(true) }
  let bin=root.appendingPathComponent("Island for ChatGPT/bin"),outside=parent.appendingPathComponent("Outside")
  try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:false);try FileManager.default.removeItem(at:bin);try FileManager.default.createSymbolicLink(at:bin,withDestinationURL:outside)
  do { try IslandPluginPackage.write(to:root,executable:binary,version:"2.10.2");preconditionFailure("Followed a symlink") } catch { check(true) }
  check(try FileManager.default.contentsOfDirectory(atPath:outside.path).isEmpty)
  print("PASS: \(count) production plugin-package checks; two hook-free manifests, exact transport paths, skill inclusion, update and unrelated-folder protection")
 }
}
