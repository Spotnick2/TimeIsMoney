---
name: client-update
description: "Handle a new WoW Forever build for TimeIsMoney: inspect shared API evidence, changed calls and measured behavior, and prepare a bounded compatibility PR. Use for a new build/API dump or client-update request."
allowed-tools: [Bash, Read, Edit, Write, Grep, Glob]
---

# New Forever build

Read CLAUDE.md and Compat.lua's API_EVIDENCE_BUILD. Run the shared forever-api-dump
skill (C:\Projects\WoW\.claude\skills\forever-api-dump\SKILL.md) first: it covers the
dump, conversion and diff. Do not mutate sibling working trees.

For its impact step, rg every changed function/event/widget against addon calls and
tests. Check argument/return/event shape.
Before updating stubs, establish the changed native signature independently.

Prepare one issue/branch/PR. Fix reachable incompatibilities, update
API_EVIDENCE_BUILD and cited filenames, then run pwsh tests/run.ps1.
The evidence constant is not a measured claim. Record actual client outcomes/build
in docs/forever-api-notes.md. Recheck item/model/currency fallbacks and relevant
save/host-timer smoke behavior. Do not claim a goblin renders because an API exists.

Commit/push only under existing owner authorization. Owner launches review/merge.
Shared addon-agnostic observations belong in the canonical porting guide when
writable/authorized; addon-specific observations remain here.
