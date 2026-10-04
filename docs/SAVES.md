# Saved games (#19)

One company per WoW account, in the account-wide SavedVariables table
`TimeIsMoneyDB`. `Sim/Save.lua` turns the simulation into plain data and back (pure
Lua, no client calls); `Host.lua` decides when to read and write it.

## Schema 1

~~~lua
TimeIsMoneyDB = {
    schema = 1,
    company = {               -- the open company, or nil
        schema = 1,
        source = "<main.js SHA-256 the simulation ports>",
        root = <node id of the game state>,
        nodes = { [id] = { key = value, ... }, ... },
        clock = { now, nextId, order, timers = { { id, kind, delay, repeat, due, order }, ... } },
        random = { s1, s2, count },            -- the host's L'Ecuyer stream
        controls = { disabled, projectElements, readouts, selects, ranges, resultsTableDisplay },
    },
    prestige = { prestigeU = n, prestigeS = n } or nil,   -- carried into the next company
}
~~~

## Encoding

- **References:** the game state is a graph. Active projects are the same tables as
  `S.projectN`, the strategy pool points into `allStrats`, and tournament results
  point at strategies. A SavedVariables writer copies tables by value, so every table
  is a numbered node and every table value a reference `{r = id}`. Shared tables stay
  shared after loading.
- **Numbers:** integers below 10^14 in magnitude are stored as numbers, so even a
  writer that prints only 14 significant digits keeps them exact. Every other number
  (fractions, huge values, NaN, infinities, -0) is stored as its exact IEEE words,
  `{w = "hhhhhhhhllllllll"}`. The hex digits are built without `string.format("%x")`,
  which raises on overflow in WoW's Lua. JavaScript's `undefined` is `{u = 1}`.
- **Timers:** every pending timer has a kind (`battle`, `main`, `slow`, `portfolio`,
  `stockShop`, `stockSell`, `pick`, `blink`, `longBlink`, `tourneyClear`,
  `tourneyLoop`). Loading rebuilds each callback from its kind, keeping its id, due
  time and stable order, so timer order continues exactly. A tournament saved between
  its chained timeouts carries on.
- **Validated on load:** the timer list must be dense, with well-formed entries
  (unique integer ids below `nextId`, nonnegative delays, a repeating timer above 0,
  due times not in the past), every kind at its fixed cadence (the main loop every
  10 ms, battles every 16 ms, ...), and each of the seven reference intervals exactly
  once. Every control part must be present (each control's state, the five messages,
  both selects, a sanitized slider value), and the random stream needs a whole draw
  count. The game state must hold every field the simulation reads, with a type it
  can hold in play (numbers, NaN included; undefined where a field starts undefined;
  the select's or slider's string for `pick` and `sliderPos`), plus every project
  record and setup table. Nested records are checked field by field: ships (at least
  `numShips` of them), battles, stocks, strategies (the pool, the picks and the
  results), the ten photonic chips with their seeds, the payoff grid, and the lists of
  numbers and names. Damaged data is refused, never shortened or filled in.
- **Timer numbers** go through the same exact encoding as the state.
- **Every timer needs a kind:** `Scheduler.register` refuses one without, so an
  unsaveable timer fails where it is made, not at the next save.
- **Outside the state table:** the controls' states, the shown project buttons, the
  messages, the select and slider values, and the results table's display state
  (`autoTourney` waits for it) are saved with the company.
- **Not saved:** the battle grid (each 16 ms update refills it from the ships), and
  functions (the slider's sanitizer is rebuilt by control id).

## When it is written

- **Logout and `/reload`:** `PLAYER_LOGOUT` writes the company just before the
  client writes SavedVariables to disk. This is the only write that reaches disk.
- **The reference auto-save** (every 25 s) keeps its timer; every twelfth one (about
  every 5 minutes) refreshes an in-memory snapshot, which costs about 10 ms in WoW. It
  is the fallback below, not a disk save. It fires inside the slow tick, before the
  scheduler requeues that timer, so the host takes the snapshot first thing in the
  next frame, before any step: a restored snapshot never replays the tick that wrote
  it, and that frame spends at most its budget. A snapshot that fails is reported at
  once ("SAVING FAILED"), with the point logout will keep.
- **A company halted by an error inside a tick** is never saved from its partly run
  tick: logout keeps the last auto-save snapshot.
- **After a prestige choice** the company is over (the reference reloads the page):
  only the prestige is kept. A new company starts with it, as the reference's
  `loadPrestige` does at page load.
- **No offline production:** a restored company continues from its saved logical
  time. A crash or forced close loses what happened since the last successful write;
  there is no automatic reload.

## Refused data

At load, `TimeIsMoneyDB` is one of:

| Contents | Result |
| --- | --- |
| nil | No company; `/tim start` opens one |
| schema 1 | The company and prestige are restored and the company resumes |
| not a table, or no numeric schema | Blocked: reported, never replaced |
| a newer schema | Blocked: reported, never replaced |
| an older schema (none exist yet) | Blocked: reported, never replaced |
| schema 1 that does not decode | Blocked: reported, never replaced |

While blocked, nothing is written at logout and `/tim start` refuses, so the data
stays exactly as found. Future schemas will add migrations from schema 1 that keep
every recoverable field.

A Codex design consult (2026-10-04) found four gaps before release, all fixed with
regression tests: the results display state, the snapshot timing, damaged timer
lists, and prestige on a new company.

## Tests

- `tests/test_save.lua`: save, write through a conservative writer (plain tables,
  numbers printed with `%.14g`), load and continue. Each of six scenarios must match
  the uninterrupted game exactly, including state, draws, controls, project buttons
  and timers: the workshop with projects blinking, a tournament between its chained
  timeouts, investments, the swarm with the slider's string, a battle in progress and
  the ending's dismantling. It also checks exact NaN, infinities, -0, subnormals,
  2^52 + 1 and `undefined`, shared references, and malformed saves.
- `tests/test_host.lua`: what logout writes for a running company, a halted one, a
  prestige choice and saved prestige.
- `tests/test_bootstrap.lua`: through the real TOC and events: a future save blocked
  and untouched, logout writing schema 1, the next load continuing at the same
  logical time, and unrecognized or broken saves kept untouched.
