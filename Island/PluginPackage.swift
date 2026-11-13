import Foundation
import Darwin

// Build self-contained, hook-free local plugin folders. No client settings change.
enum IslandPluginPackage {
    static let skill="""
    ---
    name: island
    description: Show this task's progress in the Island notch and ask clarification questions there. Use when the user requests Island progress or answers in their notch.
    ---

    Use the Island MCP connection for this task. First call connection_status. If unavailable, tell the user to open Island and enable its AI activity tool, and continue normally in chat.

    Choose a short stable task_id. Call report_progress at the start, at meaningful milestones, and at completion or failure. Send a short useful title and message, never secrets, credentials, raw tool arguments, hidden reasoning or full documents. Include a percentage only when it represents measured progress. Do not claim to observe other conversations or every tool automatically.

    Use ask_question for concise preference or clarification questions. Offer up to six choices when useful; the user can also type an answer. Wait for its actual result. If answered is false, use the original chat and do not assume an answer. Do not ask for passwords, tokens, OS approvals or client tool approvals through Island. Native security decisions remain in the client. Report completed, failed or cancelled honestly at the end.
    """
    static func write(to root:URL,executable:URL,version:String) throws {
        let fm=FileManager.default
        func directory(_ url:URL) throws {
            if !fm.fileExists(atPath:url.path) { try fm.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
            let attributes=try fm.attributesOfItem(atPath:url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,(attributes[.ownerAccountID] as? NSNumber)?.uint32Value==geteuid(),((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077==0 else { throw CocoaError(.fileWriteNoPermission) }
        }
        func safeWrite(_ data:Data,_ url:URL) throws {
            if fm.fileExists(atPath:url.path),try fm.attributesOfItem(atPath:url.path)[.type] as? FileAttributeType != .typeRegular { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to:url,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        }
        if fm.fileExists(atPath:root.path) {
            guard let marker=try? String(contentsOf:root.appendingPathComponent("ISLAND-PLUGIN.txt"),encoding:.utf8),marker.hasPrefix("Island plugin connection") else { throw CocoaError(.fileWriteFileExists) }
        } else { try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
        try directory(root)
        try safeWrite(Data("Island plugin connection\n".utf8),root.appendingPathComponent("ISLAND-PLUGIN.txt"))
        let data=root.appendingPathComponent("Local data",isDirectory:true)
        try directory(data)
        for (provider,name) in [("chatgpt-plugin","ChatGPT"),("claude-plugin","Claude")] {
            let plugin=root.appendingPathComponent("Island for "+name,isDirectory:true)
            try directory(plugin)
            for sub in ["bin","skills","skills/island",provider == "chatgpt-plugin" ? ".codex-plugin" : ".claude-plugin"] { try directory(plugin.appendingPathComponent(sub)) }
            let binary=plugin.appendingPathComponent("bin/IslandPlugin"),temp=plugin.appendingPathComponent("bin/IslandPlugin-new-"+UUID().uuidString)
            try fm.copyItem(at:executable,to:temp)
            if fm.fileExists(atPath:binary.path) { _=try fm.replaceItemAt(binary,withItemAt:temp) } else { try fm.moveItem(at:temp,to:binary) }
            try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:binary.path)
            let portable:[String:Any] = ["$schema":"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json","name":"island","version":version,"description":"Task progress and questions in your Mac’s Island. No hooks or separate account login.","license":"GPL-3.0-only"]
            let server:[String:Any] = ["command":executable.path,"args":["--directory",data.path,"--provider",provider]]
            func json(_ object:[String:Any],_ path:String) throws { try safeWrite(JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),plugin.appendingPathComponent(path)) }
            try json(portable,"plugin.json")
            var stdio=server;stdio["type"]="stdio"
            try json(["$schema":"https://agent-plugins.org/schemas/1.0.0/mcp.schema.json","mcpServers":["island":stdio]],"mcp.json")
            try json(["mcpServers":["island":server]],".mcp.json")
            if provider == "chatgpt-plugin" { try json(["name":"island","version":version,"description":"Task progress and questions in Island","skills":"./skills/","mcpServers":"./.mcp.json","interface":["displayName":"Island"]],".codex-plugin/plugin.json") }
            else {
                try json(["name":"island","version":version,"description":"Task progress and questions in Island"],".claude-plugin/plugin.json")
                try json(["manifest_version":"0.3","name":"island","display_name":"Island","version":version,"description":"Task progress and questions in your Mac’s Island","author":["name":"Island contributors"],"license":"GPL-3.0-only","server":["type":"binary","entry_point":"bin/IslandPlugin","mcp_config":["command":executable.path,"args":["--directory",data.path,"--provider",provider]]],"tools":[["name":"report_progress","description":"Send task progress to Island"],["name":"ask_question","description":"Ask a clarification question in Island"],["name":"connection_status","description":"Check the local Island connection"]],"compatibility":["platforms":["darwin"]]],"manifest.json")
                let bundle=root.appendingPathComponent("Island for Claude.mcpb"),temporary=root.appendingPathComponent("Island-Claude-new-"+UUID().uuidString+".mcpb")
                let pack=Process();pack.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");pack.arguments=["--norsrc","--noextattr","-c","-k",plugin.path,temporary.path];pack.standardOutput=FileHandle.nullDevice;pack.standardError=FileHandle.nullDevice
                try pack.run();pack.waitUntilExit();guard pack.terminationStatus==0 else { throw CocoaError(.fileWriteUnknown) }
                if fm.fileExists(atPath:bundle.path) { _=try fm.replaceItemAt(bundle,withItemAt:temporary) } else { try fm.moveItem(at:temporary,to:bundle) }
            }
            try safeWrite(Data(skill.utf8),plugin.appendingPathComponent("skills/island/SKILL.md"))
        }
        try directory(root.appendingPathComponent(".agents"));try directory(root.appendingPathComponent(".agents/plugins"))
        let marketplace:[String:Any]=["name":"island-local","interface":["displayName":"Island (this Mac)"],"plugins":[["name":"island","source":["source":"local","path":"./Island for ChatGPT"],"policy":["installation":"AVAILABLE","authentication":"ON_INSTALL"],"category":"Productivity"]]]
        try safeWrite(JSONSerialization.data(withJSONObject:marketplace,options:[.prettyPrinted,.sortedKeys]),root.appendingPathComponent(".agents/plugins/marketplace.json"))
        try "Island plugin connection\nLocal, private plugin data. Keep this folder in place while the plugins are installed.\n".write(to:root.appendingPathComponent("ISLAND-PLUGIN.txt"),atomically:true,encoding:.utf8)
        let readme="""
        Island plugins — one connection, no hooks

        1. Keep Island running and enable AI activity in Settings → Trays.
        2. For Claude Desktop, open Island for Claude.mcpb and review its installation prompt. For ChatGPT/Codex, add this folder as a local plugin marketplace and install Island from it in the plugin browser. Claude Code can also load the Island for Claude folder as a plugin. Review its MCP tools and skill, then enable it. Your existing signed-in account is used by the client; Island asks for no provider password or API key.
        3. In a new supported local chat, select the Island plugin or ask the assistant to use Island for progress and questions. Claude Code also supports loading the folder with --plugin-dir for a session.
        4. Ask it to show a progress update, then ask you a simple preference question in Island. Answer in the notch. A prepared folder is not proof that the client has installed or called the plugin.

        Keep Island installed and this folder private and in its current location. The plugin launches the transport inside the installed Island app. The bundled binary is a reference copy, not the configured command. Local data can contain the questions and status text the assistant intentionally sends. No transcript scanning, hooks, provider-token access or cloud service is used. Progress is cooperative: the assistant reports milestones through the plugin, not a universal monitor of existing chats. Native tool/OS approval remains in the original client. If a question expires, the assistant must ask in chat instead.

        ChatGPT/Codex command-line setup (review before running):\n        codex plugin marketplace add "PATH TO THIS FOLDER"\n        codex plugin add island@island-local\n\n        Local stdio plugins require a client that supports local MCP processes. Browser/cloud chats cannot reach this folder by signing in. Public distribution, a remote endpoint, and directory review are separate deployment work; this export is a local plugin package, not a published directory listing.

        To disconnect, uninstall/disable the plugin in the client and Disconnect in Island. Existing hook connections are optional legacy features and are not installed by these plugins.

        https://developers.openai.com/plugins/build/plugins
        https://code.claude.com/docs/en/plugins
        """
        try readme.write(to:root.appendingPathComponent("START HERE.txt"),atomically:true,encoding:.utf8)
    }
}
