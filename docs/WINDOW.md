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
  separators.
- **Funds show as coins** (#21), one reference unit per silver: 0.25 shows as 25c,
  1 as 1s, 123.45 as 1g 23s 45c, 1,000,000 as 10,000g.
  - The window draws the coin icons Forever's money frames use; the letters are the
    readable equivalent.
  - Amounts round to the nearest copper. Negative amounts keep their sign, and a
    value that rounds to nothing shows none.
  - Once whole copper is no longer exact (2^53 copper), only the gold shows.
  - **The exact amount on hover:** when the coins round away a fraction of a copper
    (funds, the price, gizmo and widget costs), hovering shows it, so thresholds
    stay visible.
    - The number's own text decides: 0.29 is whole copper, even though 0.29 * 100
      isn't exactly 29 in doubles.
    - While hovered, every tooltip follows the company on every redraw, a row's or
      a button's. A purchase made without moving the pointer shows the next cost.
    - The area covers the label and value, never the row's buttons, and still lets
      the window be dragged.
- **Disabled controls say so** in their label, not only in colour: "(not yet)" on
  wide buttons, "(+)" / "(-)" on the 32x32 square ones.
- **The window fits the screen.** Offers stay while the player defers them, so the
  projects card shows a page sized to UIParent's height, with Prev/Next and a page
  count to reach the rest.

## The Director's strip (#22)

Under the cards: the speaker's picture, name and line (docs/MODELS.md, "Integration").

**The line** is the plan's dialogue beat (Original Plan section 3), chosen by
`UI/Dialogue.lua` as a pure function of the saved state. It shows the last beat, in
campaign order, whose condition holds, so a reload shows the same line:

- phase I: the Director's greeting and his reactions to the first bolt, sale,
  gizmo, the computing approval, investments, negotiation, resonance and the Mind
  Control Cap network;
- after the takeover: the Ledger's reports;
- the Unlisted Director's seven letters;
- the liquidation's closing readouts;
- after a prestige restart, "New premises. New customers. Same excellent product."

The reference's own messages come back here in goblin wording in #22's second PR.

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

- **Big counts and costs** use the reference's `spellf`, ported as written over
  `formatWithCommas`: the leading group of digits with one truncated decimal, then
  the place name. 12,345,678 shows as "12.3 million ". Its quirks stay:
  - below 1,000 it adds ".0" and drops any fraction;
  - a tiny value JavaScript writes as "Ne-k" is read as text ("NaN.0 thousand ").
- **Endless countdowns:** with the slider at 0 an Active network's countdown is
  Infinity. `timeCruncher` prints JavaScript's "Infinity hours " without dividing a
  NaN, which WoW's Lua would raise on.
- **Costs are in bolts**, as the reference prices them in clips.
- **The pipeline rates** (`maps`, `wpps`, `mdps`) are presentation values the
  simulation keeps on the game (`matterRate`, `wireRate`, `exploreRate`; never
  saved). They show the last tick times 100, as the reference prints them.
- **Power figures** are recomputed from the state `updatePower` uses.
- **The next-upgrade thresholds** come from `updateUpgrades`.
- **The Work/Think slider** is a bar with << < > >> buttons that move it by 10 or
  by 1. Every value from 0 to 200 is reachable, and `Host.setValue` sanitizes each
  one as the reference's range input does.
- **In space,** probes build. The foundry and drone counts (`factoryDivSpace`,
  `droneDivSpace`) replace the build rows, and Unclaimed Material shows its
  exploration rate.
- **Network remedies:** only the remedies the simulation can reach have buttons:
  Entertain when Bored, Synchronize when Disorganized. Hungry, Confused and Cold
  (feed, teach, clad) are never set by the reference's swarm update.

## Phase III display

- **Allocation names** come from the plan: Rift Engines, Cosmic Surveying,
  Franchise Replication, Protective Wards, Foundry, Salvage and Refinery
  Deployment, and Enforcement.
- **The battle view** is the reference's 310x150 canvas, scaled to the card.
  - Live ships are 2x2 squares: loyal (left) in blue, breakaway (right) in red.
  - A destroyed ship flashes white and fades over its ten explosion frames, where
    the reference draws four expanding pixels.
  - Dots stay at least 2 px (3 for an explosion), so a scaled-down window keeps
    them visible.
  - The view redraws every 0.03 s on its own, so the explosions' 16 ms frames are
    seen. The rest of the window keeps its 0.1 s cadence.
  - Textures are pooled; a dot changes colour or size only when its ship's state
    does. The simulation's ships are only read.
- **The result** follows `checkForBattleEnd`, once Renown exists: VICTORY with the
  Renown won, or DEFEAT with the left side's ship count.
  - When both fleets fall together, its VICTORY branch runs last, so it reads
    VICTORY with the left count.
  - Numbers are written raw, without separators.
- **numberCruncher** gives the scale and the combat losses, as the reference writes
  them.
  - `toFixed` rounds ties up at every precision, decided by exact integer
    comparison against the double's binary value. The C runtime rounds ties to
    even, and this build's `%f` doesn't print exact digits. Checked against Node on
    2,000 values. It keeps "-0".
  - From 1e21 up it gives the number's own text.
  - NaN compares as in JavaScript.
- **Increase Max Trust** keeps the reference's page default cost text,
  "91,117.99". The reference's update of that text is commented out. The button is
  enabled by the real cost.

## The liquidation

The reference's ending block runs after `buttonUpdate` in the same main-loop tick,
so its hiding wins. `View.panels` applies it last, from `dismantle` and the end
timers, all of them saved state:

| Dismantling | Closes |
| --- | --- |
| 1 | The dragonling design at once. Then, by `endTimer1`: Increase Dragonling Trust (50), Increase Max Trust (100), Space Exploration (150), Combat (175), Renown (190). |
| 2 | Copper Production, and the bars come back. Then, by `endTimer2`: the network's breakthroughs (50), the network (100), the Work/Think slider (150). |
| 3 | Bolts per second, Available Bolts and the space foundry count. |
| 4 | The Negotiation Simulator. |
| 5 | Compute. Then the chips one by one by `endTimer4`: chip 10 at 10, down to chip 1 at 174. Then the Resonance Calculator (250). |
| 6 | The processors. |
| 7 | The Ledger's computing panel and the projects. |
| `endTimer6` 250 | Manufacturing. Only Make Copper Bolts remains. |

**Inside the computing panel:** `compDiv` holds Board Trust, the network's
breakthroughs, the processors, the network, the slider and the Resonance
Calculator (`trustDiv`, `swarmGiftDiv`, `processorDisplay`, `swarmEngine`,
`swarmSliderDiv`, `qComputing`). `View.panels` hides them with it. That is why
Board Trust appears with Computational Resources, not at the start.

- **Timer reads:** the reference checks `endTimer1`, `endTimer2` and `endTimer4`
  before the same tick increments them. The view reads the value the check saw
  (`View.checkedTimer`), so each closing lands on the reference's tick.
  `endTimer6` is incremented before its check.
- **Headings belong to their blocks.** The Dragonling Design and Company Network
  titles go with the design and the network. The trust increases, Renown and the
  slider that outlast them show without a heading, as in the reference.
- **One chip schedule:** `Workshop.chipTimes` drives both the wire the chips
  release and when the window hides them.

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

1. The window, the phase I Production, Sales and Ledger cards, and projects (#56).
   - The window never shows the reference's messages in their own wording. The
     Director's strip shows them as localized company reports (#22). The opening
     "Welcome to Universal Paperclips" reads "Welcome to the Time Is Money Trading
     Company." (the company the plan names).
2. Cartel Investments (risk, cash, stocks, deposit, withdraw, the
   engine upgrade), the Negotiation Simulator (Cunning, strategy picker, new and
   run tournament, auto tournaments, the report line, matchup, payoff grid and
   results) and the Resonance Calculator (the ten chips, Compute and its result)
   (#57).
3. Phase II (#58):
   - **Manufacturing:** the next upgrade, bolts per second, Available Bolts, Bolt
     Foundries with Disassemble All, and the bars until copper production starts.
   - **Copper Production:** the next drone upgrade; Unclaimed and Reclaimed
     Material and Copper Bars, each with its rate per second; Reapers and
     Converters, each with Build, +10, +100, +1k and Scrap (Disassemble All).
   - **Power:** performance, consumption by foundries and drones, production,
     stored power over capacity, Power Cores and Battery Packs.
   - **Company Network:** drones, status, the countdown to the next breakthrough,
     the remedy the status calls for, and the Work/Think slider. The breakthroughs
     row sits on the Ledger (see "The liquidation").
4. Phase III (#59):
   - **Space Exploration:** Cosmos Surveyed, Launch a Dragonling, launched,
     descendants, the losses to hazards, Charter Drift and combat (each once
     nonzero), total, and the Breakaway Franchises defeated and remaining.
   - **Dragonling Design:** Dragonling Trust used over total (and the max), the
     eight allocations with -/+ (Enforcement once unlocked), Increase Dragonling
     Trust, Increase Max Trust, and Renown.
   - **Combat:** the battle name, the battle view, the result, and the scale.
   - The prestige counters on the Production card.
5. **This slice: the liquidation.** The panels close in the reference's order
   until only manual production remains.

The Director's strip is #22. Names, icons and coins are #21. Settings, help and the
new-game control are #23.
