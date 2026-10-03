# CLAUDE.md

Shared project context. AGENTS.md points Codex here. Repository:
Spotnick2/TimeIsMoney (private). Owner: Spotnick.

## Project and status

Time Is Money is a local single-player Forever addon about an enchanted goblin
ledger making Handfuls of Copper Bolts. Faithfully port the selected Universal
Paperclips edition; apply goblin satire and Liquid Glass as presentation.

Namespace/folder/TOC: TimeIsMoney. Commands: /timeismoney, /tim.
Account-wide SavedVariables: TimeIsMoneyDB (one company per account).

M0 is initialization only: loadable scaffold, evidence pointers, tools, tests,
skills and backlog. No simulation, game save schema, glass window or models.
The scaffold never modifies saved progress. Original docs/storyboards are
committed byte-for-byte; docs/originals.json records their sizes/Git blob hashes.
Preserve the originals rather than reconstructing them from excerpts.

## Design contract

Owner-supplied docs/plan/Time-Is-Money-Implementation-Spec.md controls mechanics;
docs/plan/Time-Is-Money-Original-Plan.md controls story/terms/assets/endings.
docs/storyboard contains illustrative concepts, not formulas or verified assets.

Keep all 96 projects, three phases, recovery, both prestige routes, negative
Operations and complete liquidation. Preserve source identifiers and quirks until
parity is tested. One paperclip = one handful of bolts; wire = simulated copper bar.
One reference monetary unit displays as silver; never round persistent arithmetic
into integer copper or conflate lifetime production, stock and unsold inventory.

No offline production, WoW gold/items/Auction House integration, profession
requirements, extra currencies, rebalance, new endings, multiplayer or leaderboards.

## Architecture and layout

Three layers: pure-Lua simulation -> clock/RNG/command/save adapters -> Forever UI.
Simulation runs outside WoW with no frames/client APIs, wall clock or native RNG.
Controlled scheduler and explicit random streams drive both runners.
Node is a developer-only reference runner, never an addon runtime dependency.
Reference script order: combat.js -> globals.js -> projects.js -> main.js.
Preserve combat's 16 ms logical tick independently of UI refresh or drawing.

Current TOC: Compat.lua -> TimeIsMoney.lua. Compat owns client adaptation and
evidence build; entry point handles load/status/help only. SavedVariables are
declared but never initialized/replaced until the schema is designed.
Sim/ holds the pure-Lua simulation (docs/reference/WORKSHOP.md): parity-tested
against the reference, not in the TOC or package until #18. Unported reference
paths raise explicit errors naming their issue; never let them diverge silently.
WoW's Lua raises on x/0, x%0 and NaN division, and NaN compares true: in Sim use
JSMath.div/isNaN/lt/gt, never x ~= x or a possibly-zero divisor (forever-api-notes).

tests: Lua 5.1 loader behavior with allowlist stub and PowerShell runner.
Tools/deploy.ps1: TOC inputs and runtime media, deployed dev version only.
Tools/check_package.py: exact archive contents/version validation.
.github/workflows/package-check.yml: original byte checks, Lua checks, Windows
test/deploy execution in temporary folders, and pinned packager -d dry run.
docs/BACKLOG.md and backlog.json: recoverable issues and milestone definitions.
Tools/provision_backlog.ps1: attach issues to actual milestones; preserve issue
bodies and owner edits. The initialization-branch Actions workflow runs this script
with an issues-write token; normal package/test CI remains read-only.

Glass: reuse ..\GlassUnitFrames main through git show main:Glass.lua, because shared
working trees can be switched by another session. Retain attribution and add a
drift check. Change shared material upstream first; no glass copied in M0.

Animated goblin: adapt ..\AltStable\Plugins\Roster\AltStableRoster.lua pet rendering:
PetFrame, ReadBox, PlacePet, MeasurePet. Keep live idle, explicit camera,
bounds-based fit, bounded streaming polls/cancellation token and 2D fallback.
Read docs/MODELS.md; goblin textures/framing/emotes remain unverified.

## Client evidence and saves

Forever: Vanilla content on Mainline UI codebase. Supplied dump: 1.60.1.70170,
Interface 16001, WOW_PROJECT_ID 18. Lua 5.1/doubles are offline targets; check the
installed client runtime/numeric configuration. API names do not prove behavior.

Before adding APIs/stubs read:
C:\Projects\References\forever-api-1.60.1.70170.md
Canonical build-specific measured caveats:
C:\Projects\References\PORTING-TBC-TO-FOREVER.md
Item sources:
C:\Projects\References\forever-consumables-1.60.1.70009.md
C:\Projects\References\forever-recipes-2026-09-30.md

Scopes in docs/REFERENCES.md. Keep shared references external, not stale full copies.
Addon-specific measurements go in docs/forever-api-notes.md.

Normal logout or /reload writes progress; interrupted processes can lose progress
since the last successful write. In-memory snapshots are not disk saves. Test reload
continuation AND full exit/relaunch on a recorded build. Never automatically ReloadUI.
Versioned saves preserve recoverable data and refuse unknown future schemas.
No frames/closures serialized. Hidden/combat-collapsed windows cannot pause simulation
or duplicate host timers. Closing WoW stops simulation; no offline catch-up.

## Toolchain and validation

Lua 5.1: C:\Program Files (x86)\Lua\5.1\lua.exe and luac.exe.
pwsh tests/run.ps1 (accepts -Lua and requires a matching compiler).
pwsh Tools/deploy.ps1 (accepts -AddOnsPath).
python Tools/check_package.py .release/<archive>.zip

Default deploy: C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns.
Providing tools does not authorize deployment into the installed game.
A new addon folder needs restart. /console scriptErrors 1; /tim status.

Proportionate reachable-behavior tests. Future differential fixtures report source
hashes/time/commands/draws and first divergence; exact discrete decisions/draw counts,
narrow justified numeric tolerances with threshold evidence. Stubs cannot prove pixels.

## Workflow and skills

Issue -> main-based branch -> PR with Closes #N -> requested review -> owner squash-merges.
Owner launches reviews, merges, closes PRs and tags/releases. Never merge or
auto-merge without the owner's explicit approval; a request to merge is approval.
Commit/push only when asked; initial project request authorizes setup/publication.

Use wow-addon-review for requested reviews and post on the actual PR.
Claude /codex-consult is an explicitly requested independent pass, not an automatic
setup step; /client-update handles new build evidence. Follow global model/effort/
escalation limits; no silent stronger model/high effort or automatic delegation.

Keep diffs small; stop at the authorized milestone. Ask before new dependencies.
Confirm Paperclips reuse terms before vendoring/distributing translated source;
public source is not a license. MIT covers original/compatible attributed code,
not Paperclips or Blizzard assets. CurseForge/webhook/releases are future owner work.
