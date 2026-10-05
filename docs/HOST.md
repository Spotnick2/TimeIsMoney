# Host adapter (#18)

`Host.lua` runs the pure simulation (`Sim/`) in the Forever client. It is the only
place that touches client clocks, random seeding and commands. The simulation keeps
its own logical clock (`Sim/Scheduler.lua`); the client only decides how often to
advance it.

## Clock

- **One wakeup frame**, created at load with no parent. Hiding the UI (Alt-Z),
  closing windows or entering combat never stops it, and opening a window creates no
  timer.
- **Logical steps:** each `OnUpdate` adds the frame's real elapsed time to a debt and
  advances the game in 10 ms logical steps (`game:advanceTo(now + 10)`) while the
  debt lasts. Native timers are wakeups only: every reference interval and timeout
  still fires in the scheduler's order (due time, then a stable ordinal), so frame
  rate and wakeup batching never change outcomes (`tests/test_host.lua`).
- **Per-frame CPU budget (8 ms):** a frame stops advancing once the simulation has
  used its budget and carries the remaining debt to the next frame.
- **Debt cap (1 s):** time owed beyond one second (a loading screen, a hitch) is
  dropped and counted. The game slows down rather than freezing the client; it never
  runs ahead of real time.
- **No offline production:** logical time moves only while a session runs. Saves
  continue from the saved logical time, not from the wall clock (docs/SAVES.md).

## Random stream

L'Ecuyer's (1988) combined multiplicative congruential generator
(m1 = 2147483563, a1 = 40014; m2 = 2147483399, a2 = 40692). Every product stays
below 2^47, so double arithmetic is exact on every host, including WoW's Lua; the
period is about 2.3 × 10^18; draws are in (0, 1); the state is two integers that the
save stores with the draw count. A new company is seeded from the server time and the profiler clock. Parity
traces keep using recorded streams. Cosmetic randomness (glass, the Director) must
use a separate stream so it cannot change outcomes.

## Commands

`Host.click(id)` and `Host.setValue(id, value)` accept only known controls and apply
them at the current logical time, between scheduler callbacks. A control the game
refuses (an unported path, a project button not shown) raises before changing state;
the host reports it and the game keeps running.

**Restarts (#23).** A click that ends the company requests the restart into a new
game (`game.restartRequested`, with the prestige in `game.savedPrestige`): a prestige
choice, or Quantum Temporal Reversion after the window's confirmation. The host then
starts the next company at once with that prestige (`Host.restart`). The old one is
never run again, so a reward cannot be collected twice. This is the reference's
`reset()`: the company's save is cleared and the prestige kept. The new-game control
(`Host.newGame`, behind an explicit confirmation) does the same. A restart is refused
while saving is off, so blocked data is never replaced.

An error inside a tick halts the simulation: the tick has partly run, so it must not
continue.

Until the ledger window (#20), developer slash commands drive it: `/tim start`,
`/tim status` (logical time, clips, funds, wire, CPU per frame, dropped time),
`/tim click <control>` and `/tim set <control> <value>`. `/tim start` opens a company
only when there is none and saving is not blocked.

## Auto-save

The reference saves to browser storage every 250 slow ticks (25 s) without changing
game state. The port keeps that timer and calls `game.onSave`, which refreshes the
host's in-memory snapshot; the disk write happens at logout (docs/SAVES.md).

## Measured cost

On client 1.60.1.70205 the simulation keeps up in real time: 0.67 ms of CPU per frame
on average, the worst frame at the 8 ms budget, no time dropped and flat memory over
151 logical seconds (docs/forever-api-notes.md, "#18 host adapter in the client").
The first deploy allocated about 1.16 MB of garbage per logical second (battle grid
lists and discarded scheduler log entries); the client grid lists are now reused and
the host passes no log, which `tests/test_host.lua` guards.
