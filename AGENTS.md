# AGENTS.md

Shared entry point for Codex and other non-Claude agents. Read CLAUDE.md first;
it owns project facts, mechanics, layout, validation and workflow.

- Work queue: Spotnick2/TimeIsMoney issues. Work one bounded issue/milestone at a time.
- Target: WoW: Forever, Interface 16001; offline compatibility: Lua 5.1.
- Validate: pwsh tests/run.ps1. Keep @project-version@ in the source TOC.
- Reviews: use $wow-addon-review in .agents/skills/wow-addon-review/. Post every
  requested PR review on that PR and link it in the final response.
- Codex only: during PR reviews, rely on tests already run in the main session;
  do not rerun them. Report that evidence and any validation limitations.
  This exception does not apply to Claude.
- Global owner model/effort limits remain authoritative. A review skill's model
  recommendation does not authorize escalation. No automatic subagent delegation.
- Issue -> branch off main -> PR with Closes #N -> owner-requested review ->
  owner squash-merges. Do not merge or enable auto-merge without the owner's
  explicit approval; an owner request to merge is that approval.
- Commit/push only when requested. This initialization request authorizes the
  initialization branch, commits, issue backlog and PR.

The project review skill is also installed for Claude; keep both copies identical.
Use the OpenAI developer docs MCP first for OpenAI/Codex setup questions.
.codex/config.toml declares the official server for a trusted local checkout.
Remote configuration does not make tools callable in this running session; verify
local activation with codex mcp list after checkout synchronization.
