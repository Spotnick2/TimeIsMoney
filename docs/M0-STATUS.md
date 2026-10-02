# M0 completion evidence

PR [#26](https://github.com/Spotnick2/TimeIsMoney/pull/26) stays draft and issue
[#1](https://github.com/Spotnick2/TimeIsMoney/issues/1) stays open until every gate passes.

| Gate | Evidence / remaining action |
| --- | --- |
| Original design inputs | Both plan files and both PNGs are committed as the original bytes. originals.json records source byte sizes/Git blob hashes; CI verified all four. Plan files use -text attributes to preserve bytes on Windows. |
| Milestones and backlog | Six actual milestones exist; all 25 issues are attached. [Provisioning run](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37068534961) passed. |
| Offline Lua/package | [Package check](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37068541649) passed Lua 5.1 bootstrap, original byte verification, PowerShell parsing, packager dry run and exact four-file package/version checks. |
| Windows tooling | The same run built the declared Lua 5.1 toolchain from checksum-verified official Lua 5.1.5 source, executed tests/run.ps1, and exercised deployment into a temporary AddOns folder. Checks include nested media bytes, dev version, repeat install, source preservation, missing input and traversal rejection. No game folder was touched. |
| Local checkout | Pending. The owner repaired Git trust, but Codex's shell process still fails before commands execute. The current local repo was last observed on unborn main with untracked docs; do not overwrite or discard those files to synchronize it. |
| OpenAI docs MCP | .codex/config.toml declares the official HTTP endpoint for a trusted local project. Local activation remains unverified while checkout/shell access is blocked. Confirm with codex mcp list from the synchronized checkout. |
| Forever client load | Pending. Deploy the scaffold, restart for its first installation, enable /console scriptErrors 1, and run /tim help and /tim status. Record the actual build/interface/Lua, output, and errors or their absence in forever-api-notes.md. |

The toolchain source checksum is from [Lua's official download index](https://www.lua.org/ftp/).
MCP configuration follows [OpenAI Docs MCP setup](https://developers.openai.com/learn/docs-mcp)
and [project config guidance](https://learn.chatgpt.com/docs/config-file/config-basic).
Codex loads project configuration only for trusted projects. A committed configuration
is not proof that the current client has connected to the server.

For user-wide installation instead of project scope, the documented command is:

```powershell
codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp
codex mcp list
```

GitHub CLI is installed on the owner's machine. The local blocker occurs during
Codex shell startup, before either gh or Git can execute. GitHub Actions ran the
existing gh provisioning script successfully; that does not repair local shell access.

Follow-up review should check the committed originals and byte-preservation rules,
Windows validation and milestone attachments. Before merge it must also verify
the remaining local/client observations. No gameplay, game save schema, UI or
goblin rendering is implemented by M0.
