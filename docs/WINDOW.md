# The ledger window (#20)

`/tim` opens or closes the window over the running company (`/tim start` opens a
new company and its window). It is built from plain, unprotected frames drawn with
the embedded LibGlass-1.0 material.

## Rules

- **Read-only view.** `UI/View.lua` is a pure function of the game: panel visibility,
  labels, display text and the projects on offer. It runs outside WoW in tests. A
  test refreshes the window repeatedly and checks that the state, the control states,
  the messages and the random draw count are unchanged.
- **Commands go through the host.** Every button calls `Host.click(id)` with its
  reference control id. A refused command is reported in chat, and nothing changes.
- **Hidden means not drawn, never paused.** The window redraws every 0.1 s, only
  while shown. The simulation runs on the host's own parentless wakeup frame, so
  closing the window, Alt-Z or combat never pause it, and reopening creates no timer.
- **Panels follow `buttonUpdate`.** Visibility uses the reference's own conditions
  in its order, including its strict comparisons. `creativityOn === 0` never holds,
  because `creativityOn` is a boolean, so the Ingenuity row shows whenever the
  Ledger does.
- **Display rounding never decides anything.** Counts are whole numbers with
  separators. Funds show as coins, one reference unit per silver (0.25 shows as 25c,
  1,000,000 as 10,000g). Coin icons and threshold tooltips are #21.
- **Disabled controls say so** in their label, not only in colour: "(not yet)" on
  wide buttons, "(+)" / "(-)" on the 32x32 square ones.
- **The window fits the screen.** Offers stay while the player defers them, so the
  projects card shows a page sized to UIParent's height, with Prev/Next and a page
  count to reach the rest.

## Selects and presentation state

- **Selects** (risk, strategy) are buttons showing the selected option. A click
  opens the list of options. Choosing one sets it through `Host.setValue` in a
  single step, as choosing it in the reference does; no option in between is ever
  set.
- **Presentation-only values live on the game, never in the state or the save.**
  The simulation keeps them where the reference writes display text, and consumes
  the same draws as before:
  - `game.gridLabel`: the move-name pair the payoff grid drew.
  - `game.tourneyReport`: `tourneyDisplay`. It starts as the reference's opening
    text, shows "Round n" while rounds play, then the results heading.
  - `game.matchup`: `vertStrat`/`horizStrat`, the current round's two strategies.
  - `game.qCompResult`: the Compute result. `false` means no chips; otherwise it
    holds the unclamped qOps.

  After a reload they read as at the start, until the next tournament or compute.
- **The View builds the text** with the plan's terms ("Need Arcane Crystals",
  "gain Cunning"). The Compute line fades with `S.qFade`, as the reference's opacity
  does.
- **Tournament grid and results:** both tables start shown, the results one empty.
  After a tournament the results replace the grid, with the picked strategy
  (`strats[pick]`) marked.
- **Hovering the tournament area** is the reference's `tournamentStuff` mouseover
  and mouseout, sent as host commands (`tournamentStuff:mouseover` and `:mouseout`,
  Game:revealGrid and Game:revealResults).
  - Entering shows the grid and resets `resultsTimer`, which holds automatic
    tournaments; leaving shows the results again.
  - The area keeps one size for both views, so the swap never moves the pointer
    out of it.
  - Pointer moves on a stopped company are not reported.
- **Stocks** show the reference's whole numbers (`Math.ceil`), two lines per stock.
  After a sale, the slot just past the last stock keeps what it showed. This
  reproduces the reference's off-by-one clear (the "Frank Fix" comment); later
  slots are blank.
- **The window fits the screen in both directions.** A column too tall for the
  screen continues in the next one. If the window is still larger than the screen
  (open selects, many columns), it scales down to fit.

## Phase II display

- **Big counts and costs** use the reference's `spellf`: the leading group of
  digits with one truncated decimal and the place name, so 12,345,678 shows as
  "12.3 million". Below 1,000 the reference adds ".0" and drops any fraction.
- **Costs are in bolts**, as the reference prices them in clips.
- **The pipeline rates** (`maps`, `wpps`, `mdps`) are presentation values the
  simulation keeps on the game (`matterRate`, `wireRate`, `exploreRate`; never
  saved). They show the last tick times 100, as the reference prints them.
- **Power figures** are recomputed from the state `updatePower` uses.
- **The next-upgrade thresholds** come from `updateUpgrades`.
- **The Work/Think slider** is a bar with -/+ buttons that set the range 10 at a
  time through `Host.setValue`, which sanitizes it as the reference's range input
  does.
- **Network remedies:** only the remedies the simulation can reach have buttons:
  Entertain when Bored, Synchronize when Disorganized. Hungry, Confused and Cold
  (feed, teach, clad) are never set by the reference's swarm update.

## Project text

`UI/ProjectText.lua` is generated by `Tools/make_project_text.py` from plan Appendix A
(each title and its purpose) and from the pinned reference `projects.js` (the price
tags). The UI rebuilds the four price tags the reference computes (`project40b`,
`project51`, `project133`, `project216`) from the current state, and renames the
units (ops to Operations, creat to Ingenuity, Trust to Board Trust, yomi to
Cunning). CI's `--check` keeps the file in step with both sources.

`project216`'s tag shows the current standard Operations. The reference fixes that
number in the tag when `project215` is bought; it is display only.

## Slices

1. The window, the phase I Production, Sales and Ledger cards, projects, and the
   newest message line (#56).
2. Cartel Investments (risk, cash, stocks, deposit, withdraw, the
   engine upgrade), the Negotiation Simulator (Cunning, strategy picker, new and
   run tournament, auto tournaments, the report line, matchup, payoff grid and
   results) and the Resonance Calculator (the ten chips, Compute and its result)
   (#57).
3. **This slice, phase II:**
   - **Manufacturing:** the next upgrade, bolts per second, Available Bolts, Bolt
     Foundries with Disassemble All, and the bars until copper production starts.
   - **Copper Production:** the next drone upgrade; Unclaimed and Reclaimed
     Material and Copper Bars, each with its rate per second; Reapers and
     Converters, each with Build, +10, +100, +1k and Scrap (Disassemble All).
   - **Power:** performance, consumption by foundries and drones, production,
     stored power over capacity, Power Cores and Battery Packs.
   - **Company Network:** drones, status, the countdown to the next breakthrough,
     the remedy the status calls for, breakthroughs, and the Work/Think slider.
4. Phase III: the probe design, combat view and allocations.
5. The liquidation sequence, closing the panels in order until only manual
   production remains.

The Director's strip is #22. Names, icons and coins are #21. Settings, help and the
new-game control are #23.
