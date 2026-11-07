# Island agent connections

Island supports local ChatGPT Work/Codex, Claude Code and Cursor hook sessions. The native IslandBridge executable is built from IslandBridge.swift; it records bounded JSON events in a private local folder and returns a single decision for an active permission request. It does not run agent commands, read transcript files or create persistent allow rules.

## ChatGPT Work and Codex

1. Enable **AI Coding** and **Inbox** in Settings → Modules.
2. Prepare a private, unsynced folder under Settings → Agents & Inbox. Island exports the signed helper, `chatgpt-codex-hooks.example.json`, a plugin folder and client instructions.
3. Use either the hook example in your local `~/.codex/hooks.json` / project hook configuration, or the generated plugin. Preserve existing handlers. Do not install both forms, which would duplicate requests.
4. In the desktop app select **Review hooks** above the composer or **Settings → Hooks**. In the CLI use `/hooks`. Review and trust the six Island definitions. Island does not alter the trust database or bypass this step.

The six events are SessionStart, UserPromptSubmit, PermissionRequest, Stop, Interrupt and SessionEnd. The bridge receives only the fields present in those local events. It records metadata, the last assistant message when supplied, and tool arguments for permission review, so keep the folder private. It ignores transcript paths. No separate API key is needed for this local connection.

This applies to local Work/Codex sessions on this Mac. Plain web chats do not publish these local events, and cloud-hosted Work environments do not execute scripts installed on your Mac. The module also opens a question as a draft in the ChatGPT desktop app; it never submits the draft. Valid connected session IDs can open their chat.

[OpenAI hook reference](https://learn.chatgpt.com/docs/hooks), [desktop draft and chat links](https://learn.chatgpt.com/docs/reference/commands), [plugin support and environment limits](https://learn.chatgpt.com/docs/plugins).

## Claude Code and Cursor

Generated examples preserve your existing client configuration. Merge the intended hooks into your client’s own settings. Claude Code and ChatGPT/Codex PermissionRequest allow/deny responses apply once; expiry returns no decision so the client retains its usual prompt. Cursor beforeShellExecution/beforeMCPExecution timeout declines. Allow never creates an always-allow rule. Review the complete request before choosing Allow once.

[Claude Code hooks](https://code.claude.com/docs/en/hooks), [Cursor hooks](https://cursor.com/docs/hooks).

## Privacy and inbox

The folder stores tool arguments and may include sensitive text. Files are owner-only where written by the transport; event directories are private. Input is bounded, oversized requests cannot be approved, and decisions require matching random IDs/nonces. Events disappear from Island’s view after 24 hours; disk cleanup runs on later incoming events. Disconnecting removes the bookmark, not your files or client hooks. Remove the hooks in the client to stop forwarding.

Update bridge files preserves the existing generated files in a private backup folder. Review changed hooks before trusting them again.

Inbox includes Island’s own alerts and explicitly forwarded notices; it is not a reader for arbitrary Notification Center histories. Scripts can forward title/body JSON on stdin to:

```sh
/path/to/IslandBridge --directory /private/chosen/folder --provider relay --event Notification
```

## Verification

Production CLI fixtures cover ChatGPT/Codex/Claude/Cursor allow, deny, expiry, malformed Boolean decisions, wrong nonce and oversized inputs. No real agent command is authorized by a fixture. Actual client trust and a real session event are separate live checks.

Optional cloud translation uses [OpenAI Responses](https://developers.openai.com/api/reference/typescript/resources/responses/methods/create), with a separate user-chosen model and Keychain API key. It sends only on Translate with OpenAI selected and sets store:false. Tests use local response fixtures and make no paid API request.
