---
name: client-update
description: "Handle a new WoW Forever build for TimeIsMoney: inspect shared API evidence, changed calls and measured behavior, and prepare a bounded compatibility PR. Use for a new build/API dump or client-update request."
allowed-tools: [Bash, Read, Edit, Write, Grep, Glob]
---

# New Forever build

Read CLAUDE.md and Compat.lua's API_EVIDENCE_BUILD. TimeIsMoney does not own dump
tooling: ..\AltStable\Tools\ForeverAPIDump and C:\Projects\References own the shared
dump/converters. Do not delete old dumps or mutate sibling working trees.
If the requested build dump exists, use it. Otherwise ask the owner to generate
it in-client with /apidump, then run the shared converter only when access is authorized.

Use the shared Compare-Dumps.ps1 workflow; rg every changed function/event/widget
against addon calls and tests. Documented sections are native evidence; _G addon
walks alone are not compatibility findings. Check argument/return/event shape.
Before updating stubs, establish the changed native signature independently.

Prepare one issue/branch/PR. Fix reachable incompatibilities, update
API_EVIDENCE_BUILD and cited filenames, then run pwsh tests/run.ps1.
The evidence constant is not a measured claim. Record actual client outcomes/build
in docs/forever-api-notes.md. Recheck item/model/currency fallbacks and relevant
save/host-timer smoke behavior. Do not claim a goblin renders because an API exists.

Commit/push only under existing owner authorization. Owner launches review/merge.
Shared addon-agnostic observations belong in the canonical porting guide when
writable/authorized; addon-specific observations remain here.
