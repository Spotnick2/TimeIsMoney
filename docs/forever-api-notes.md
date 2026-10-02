# Time Is Money client measurements

M0 scaffold load and command responses are recorded below. Gameplay, saved-state
continuation and rendering are not implemented or verified by these observations.

## M0 local installation — 2026-10-02

- Local Lua 5.1 bootstrap and PowerShell deployment integration tests passed.
- Tools/deploy.ps1 installed the scaffold into
  C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TimeIsMoney.
  The folder contains Compat.lua, TimeIsMoney.lua, TimeIsMoney.toc and LICENSE;
  installed code/license hashes match source, and the installed TOC uses Version: dev.
- The running _classic_beta_ WowB.exe file/product version is 1.60.1.70170.
  This is executable metadata, not a recorded GetBuildInfo result.
- The game was already running at first installation; the owner was instructed
  to restart normally and enable /console scriptErrors 1 before the check.
- The owner then supplied these successful in-game responses on 2026-10-02:

  > [17:56:29] Time Is Money: /tim (also /timeismoney) - project status. /tim status - runtime details.
  >
  > [17:57:44] Time Is Money: Scaffold only; gameplay is not implemented. Client 1.60.1.70170, Interface 16001, Lua 5.1. API evidence: 1.60.1.70170.

  These confirm scaffold load, slash dispatch and the actual GetBuildInfo/_VERSION
  status path. No Lua error was reported; a separate explicit confirmation about
  error dialogs was not supplied. No numeric configuration, rendering or disk
  persistence claim follows from these command responses.
- codex mcp list --json confirmed the project OpenAI docs server is enabled at
  https://developers.openai.com/mcp. No tool availability claim is made for this
  already-running Codex session.

## Future probes

Supplied API evidence: 1.60.1.70170, Interface 16001. Shared measurements from
AltStable and the canonical porting guide retain their own tested builds.

Record date, actual GetBuildInfo result, runtime Lua/numeric observations,
reproduction, expected/observed result and fallback for each client measurement.

Early smoke (#9): addon load/commands, established item icon, battery 274048,
profession/spell icon, optional creature model, reload and full exit/relaunch.
Goblin probe (#10): texture/framing/idle/emotes/loading/input/frame time.
Later: all project assets, hidden-window timers/performance, coin/large-number
display, schema migration/continuation and endings.
