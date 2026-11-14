# Island AI plugins

The primary connection is a hook-free local MCP plugin. It reports task milestones and asks clarification/preference questions; users answer in Island with an option or free text. Island does not request provider passwords or API keys. The assistant continues to use the account signed in to its own client. This does not provide a universal stream of every existing chat, native approval interception, or hidden reasoning.

## Set up once

1. Open Island Settings → Agents & Inbox → Get the plugins. Choose a private local parent folder. Island creates **Island Plugins**, exports the two packages and connects to its Local data folder. This enables AI Activity.
2. For Claude Desktop, open **Island for Claude.mcpb** and review its extension prompt. The package follows the MCPB 0.3 binary-server format. For Claude Code, load the **Island for Claude** folder as a local plugin.
3. For ChatGPT/Codex, add the exported folder as a local plugin marketplace and install **Island**. Supported CLI commands are `codex plugin marketplace add "/absolute/path/Island Plugins"` followed by `codex plugin add island@island-local`. Installation and any required tool review belong to the client; Island never edits its trust records.
4. Start a new supported local chat and enable/select Island. Its skill asks the assistant to report meaningful milestones and clarification questions for multi-step work. Use **Copy connection-test message** in Island to test one harmless progress update and preference question. **Prepared files are not proof of client installation or a successful tool call.**

After updating Island, use **Update plugin files**, reinstall the updated client package and start a new chat. Existing exported files also refresh on app-version changes; this does not change client trust or reinstall a Claude extension automatically. Each client’s heartbeat and last activity are shown separately in Agents & Inbox.

Supported local work sessions can use the generated skill’s `--call` fallback if the enabled plugin’s MCP tools are not exposed. It accepts only the same three tools and one JSON argument object on standard input. Progress uses a stable provider/task ID across MCP and direct calls. Questions wait for a real nonce-matched user reply and expire normally; input EOF does not answer or cancel them. This fallback needs local execution support and must not be used to override an intentional client policy restriction. Ordinary browser/cloud chats cannot use this local route.

The packages launch the helper inside the installed Island app. This avoids requiring execution approval for a new copied helper from a sandbox export; no quarantine flags or OS protections are changed. Keep Island installed.

The local server exposes only `connection_status`, `report_progress` and `ask_question`. The assistant reports meaningful milestones, not a made-up percentage. Questions expire, can be cancelled by the client, and require matching random IDs/nonces for replies. Native tool/OS approvals remain in the client. The server executes no task commands and accesses no provider tokens, transcript history or network service. A missing app heartbeat makes questions fail closed; the assistant must ask in the original chat instead.

Keep the exported folder in place and private. Status and question text are stored locally. Responses are removed after consumption. Event history is bounded and old records are pruned. The native app identifies a reporting plugin by its actual local heartbeat; exporting a folder alone never shows Connected. Disconnect in Island and disable/uninstall the plugin in the client to stop forwarding. A folder bookmark is not a provider login.

Local stdio plugins require a compatible local client. Browser/cloud sessions cannot reach this Mac’s folder through sign-in alone. Remote hosting, authentication and public directory submission are separate deployment work; no plugin was published by this local build.

Primary references: [OpenAI plugin packages and local marketplaces](https://developers.openai.com/plugins/build/plugins), [Claude plugin MCP support](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers), [MCPB desktop extensions](https://github.com/modelcontextprotocol/mcpb).

## Legacy connections (optional)

Island supports local ChatGPT Work/Codex, Claude Code and Cursor hook sessions. The native IslandBridge executable is built from IslandBridge.swift; it records bounded JSON events in a private local folder and returns a single decision for an active permission request. It does not run agent commands, read transcript files or create persistent allow rules.

### Legacy ChatGPT Work and Codex

1. Enable **AI Activity** and **Inbox** in Settings → Modules.
2. Use **Advanced → Older client connections** under Settings → Agents & Inbox to prepare a private, unsynced folder. Island exports the signed helper, `chatgpt-codex-hooks.example.json`, a plugin folder and client instructions.
3. Use either the hook example in your local `~/.codex/hooks.json` / project hook configuration, or the generated plugin. Preserve existing handlers. Do not install both forms, which would duplicate requests.
4. In the desktop app select **Review hooks** above the composer or **Settings → Hooks**. In the CLI use `/hooks`. Review and trust the six Island definitions. Island does not alter the trust database or bypass this step.

The six events are SessionStart, UserPromptSubmit, PermissionRequest, Stop, Interrupt and SessionEnd. Interrupt and SessionEnd use the client’s three-second maximum; the other hooks retain a 60-second limit so permission review can finish. The bridge receives only the fields present in those local events. It records metadata, the last assistant message when supplied, and tool arguments for permission review, so keep the folder private. It ignores transcript paths. No separate API key is needed for this local connection.

This applies to local Work/Codex sessions on this Mac. Plain web chats do not publish these local events, and cloud-hosted Work environments do not execute scripts installed on your Mac. Valid connected legacy session IDs can open their chat.

[OpenAI hook reference](https://learn.chatgpt.com/docs/hooks), [desktop draft and chat links](https://learn.chatgpt.com/docs/reference/commands), [plugin support and environment limits](https://learn.chatgpt.com/docs/plugins).

### Legacy Claude Code and Cursor

Generated examples preserve your existing client configuration. Merge the intended hooks into your client’s own settings. Claude Code and ChatGPT/Codex PermissionRequest allow/deny responses apply once; expiry returns no decision so the client retains its usual prompt. Cursor beforeShellExecution/beforeMCPExecution timeout declines. Allow never creates an always-allow rule. Review the complete request before choosing Allow once.

[Claude Code hooks](https://code.claude.com/docs/en/hooks), [Cursor hooks](https://cursor.com/docs/hooks).

### Legacy privacy and inbox

The folder stores tool arguments and may include sensitive text. Files are owner-only where written by the transport; event directories are private. Input is bounded, oversized requests cannot be approved, and decisions require matching random IDs/nonces. Events disappear from Island’s view after 24 hours; disk cleanup runs on later incoming events. Disconnecting removes the bookmark, not your files or client hooks. Remove the hooks in the client to stop forwarding.

Update bridge files preserves the existing generated files in a private backup folder. Review changed hooks before trusting them again.

Inbox includes Island’s own alerts and explicitly forwarded notices; it is not a reader for arbitrary Notification Center histories. Scripts can forward title/body JSON on stdin to:

```sh
/path/to/IslandBridge --directory /private/chosen/folder --provider relay --event Notification
```

## Verification

Production CLI fixtures cover ChatGPT/Codex/Claude/Cursor allow, deny, expiry, malformed Boolean decisions, wrong nonce and oversized inputs. No real agent command is authorized by a fixture. Actual client trust and a real session event are separate live checks.

Optional cloud translation uses [OpenAI Responses](https://developers.openai.com/api/reference/typescript/resources/responses/methods/create), with a separate user-chosen model and Keychain API key. It sends only on Translate with OpenAI selected and sets store:false. Tests use local response fixtures and make no paid API request.
