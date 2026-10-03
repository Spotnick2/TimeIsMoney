---
name: codex-consult
description: "Run an explicitly requested independent Codex CLI design or code review for TimeIsMoney. Use for an adversarial second opinion or rubber-duck request; do not launch automatically during routine implementation."
allowed-tools: [Bash, Read, Write]
---

# Consult Codex

Follow the owner's global model/effort policy. Use the configured default model
and medium effort; ask before stronger/high effort. Do not infer authorization
from this skill's presence or silently adopt the owner's review model.

Write a scoped prompt to a scratch file and feed it via stdin. Use codex exec with
--ephemeral, --skip-git-repo-check, -s read-only, -o <verdict>, and
-c model_reasoning_effort=medium. In Bash wrap with timeout 300; capture stdout/stderr
in a progress file. In PowerShell use redirected stdin/stdout and a bounded wait
on the exact process created (Start-Process -WindowStyle Hidden). Kill only that PID,
never other Codex sessions by name. No nested agents unless explicitly authorized.

For prose-only advice say evidence is in the prompt. For code review allow reading
files/shell commands in the read-only sandbox; "no commands" would prevent inspection.
Provide CLAUDE.md, actual committed diff/head, relevant plan/issue and build evidence.
Source references:
C:\Projects\References\PORTING-TBC-TO-FOREVER.md
C:\Projects\References\forever-api-1.60.1.70205.md
docs/REFERENCES.md and docs/MODELS.md when relevant.

Good bounded surfaces: JS/Lua numeric translations, scheduler/RNG consumption,
save continuation or model loading/framing. Ask for concrete reachable defects and
accept "no defect found"; do not solicit complexity for a single-owner addon.
Read the -o verdict file, verify each finding against evidence, and report it.
If asked for an actual PR review, use wow-addon-review's scope and posting contract.
CLI unavailable: report that limitation; don't pretend another model reviewed.
