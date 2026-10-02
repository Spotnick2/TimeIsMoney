# M0 completion evidence

The M0 setup gates below are complete. PR [#26](https://github.com/Spotnick2/TimeIsMoney/pull/26)
is prepared for the requested follow-up review. Issue
[#1](https://github.com/Spotnick2/TimeIsMoney/issues/1) stays open until the owner merges.

| Gate | Evidence / remaining action |
| --- | --- |
| Original design inputs | Both plan files and both PNGs are committed as the original bytes. originals.json records source byte sizes/Git blob hashes; CI verified all four. Plan files use -text attributes to preserve bytes on Windows. |
| Milestones and backlog | Six actual milestones exist; all 25 issues are attached. [Provisioning run](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37068534961) passed. |
| Offline Lua/package | [Package check](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37069038931) passed Lua 5.1 bootstrap, original byte verification, PowerShell parsing, packager dry run and exact four-file package/version checks. |
| Windows tooling | The same run built the declared Lua 5.1 toolchain from checksum-verified official Lua 5.1.5 source, executed tests/run.ps1, and exercised deployment into a temporary AddOns folder. Checks include nested media bytes, dev version, repeat install, source preservation, missing input and traversal rejection. No game folder was touched. |
| Local checkout | Complete. Origin is configured; chore/initialize-project tracks its remote branch and main tracks origin/main. Existing local originals matched the remote blob hashes before checkout, and no extra local commit was created. Local tests/run.ps1 and tests/test_deploy.ps1 passed on 2026-10-02. |
| OpenAI docs MCP | Complete configuration. .codex/config.toml declares the official HTTP endpoint; local codex mcp list --json reports openaiDeveloperDocs enabled with https://developers.openai.com/mcp. This does not establish tool availability in this already-running session. |
| Forever client load | Complete for the M0 scaffold. Tools/deploy.ps1 installed the four-file scaffold into the actual _classic_beta_ AddOns folder; code/license bytes and dev TOC were verified. The owner supplied successful /tim help at 17:56:29 and /tim status at 17:57:44 on 2026-10-02. Status reports client 1.60.1.70170, Interface 16001 and Lua 5.1. No Lua error was reported. See forever-api-notes.md for the exact responses and limits. |

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

GitHub CLI is installed on the owner's machine. General shell launch initially
failed during sandbox setup; launching through the already-approved PowerShell
executable worked. Local Git synchronization, tests and MCP checks then completed.

Follow-up review should check the committed originals and byte-preservation rules,
Windows validation and milestone attachments. The recorded local/client observations
establish M0 loading and commands only. No gameplay, game save schema, UI or
goblin rendering is implemented by M0.
