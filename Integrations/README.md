# Island local bridge

IslandBridge is a small native command-line transport bundled inside Island.app and built from IslandBridge.swift. It executes no agent commands. Both the app and client hooks exchange JSON in a local folder you choose. No HTTP server or cloud account is required.

In Settings → Modules enable AI Coding and/or Inbox. In Settings → Agents & Inbox choose a new private, unsynced folder. Island exports the signed helper plus Claude Code/Cursor example configurations. Review and merge the examples into the intended client's settings, preserving existing hooks. Island never edits those settings automatically. To disconnect fully, remove the installed hooks from your client and disconnect the folder in Island.

Claude PermissionRequest asks for a single allow/deny decision. If unanswered, Island returns an empty response so Claude keeps its own normal permission flow. Cursor beforeShellExecution uses allow/deny and declines on timeout. No always-allow rule is generated. The request must have a matching random ID and nonce; expired or malformed responses are ignored. Review the full tool arguments before allowing anything. Local event files may contain those arguments: keep the folder private and outside cloud syncing.

The helper bounds input and event history. Events expire from Island's view after 24 hours, with disk cleanup performed on later incoming events. Explicitly forwarded notices are an inbox; this is not a reader for arbitrary macOS Notification Center content.

A script can forward a notice by sending JSON with title/body to:

```sh
/path/to/IslandBridge --directory /private/chosen/folder --provider relay --event Notification
```

Supply JSON on standard input. Quoted real paths and client-specific hook schemas matter; use the generated examples for your chosen folder.

Protocol reference: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Cursor hooks](https://cursor.com/docs/hooks). The automated tests run synthetic requests through the real compiled helper, including one-time allow, deny, expiry, malformed booleans, wrong nonce and oversized inputs. No actual agent tools or shell commands are authorized during tests. Real client configuration remains a separate live check.

Optional cloud translation uses [OpenAI Responses](https://developers.openai.com/api/reference/typescript/resources/responses/methods/create). It sends only on Translate with OpenAI selected, uses a Keychain key, requests store:false, and rejects incomplete/refused responses. The tests use local response fixtures; no paid API request was made.
