# Presentation assets (#21)

`UI/Assets.lua` holds two things: the plan's 14 item identities (Appendix B), and an
icon family for every one of the 96 projects. A research family shares one icon, as
the plan asks.

**Sources.** Item and spell IDs are database-listed: from the plan's research
(2 October 2026) and the supplied Forever recipe snapshot (`forever-recipes-2026-09-30.md`,
crafted item IDs). A database entry is not an in-client rendering test. Every entry's
status stays `database-listed` until it is checked in the client.

## Resolution

Resolution never waits on an event. All client calls go through `TIM.API` in
Compat.lua.

- **Items:** `C_Item.GetItemIconByID`, polled on each lookup. On 1.60.1.70205 it
  answered at once for the uncached 9-60 Battery Pack, while no item-load event
  arrived within 10 s (forever-api-notes, #9).
  - A nil answer requests the item's data once. The item stays `pending` until the
    icon answers or 10 s pass, then falls back for good.
  - `ITEM_DATA_LOAD_RESULT` only shortens the wait: a failed load falls back at
    once.
  - The question mark's file ID (134400) counts as a missing item, never as
    resolved.
- **Spells:** `C_Spell.GetSpellTexture` by ID (spell data is local).
- **Texture paths** are used as given. Only the client can show whether they exist.
- **Fallback:** `Interface\Icons\INV_Misc_QuestionMark`.
- **Caching:** final answers are kept per source, so redraws don't look up again,
  and the window sets a texture only when it changes.

## Checking in the client

`/tim icons` lists every identity and family with its icon and status. Only
resolved is green:

- `resolved` (green);
- `pending` (yellow);
- `path` (amber: a texture path, unchecked);
- `fallback` (red).

The panel looks again twice a second while open. Hovering an entry shows its source
ID, URL, and the projects that use it.

Record the result per entry below:
- the build tested;
- `client-verified` when the icon renders as intended;
- `fallback-required`, with a replacement verified Forever asset, when it does not.

## Catalog

**Client check, 2026-10-05.** Done on the owner's Forever client: 1.60.1.70205, the
build of the last recorded measurement. `/tim status` prints the exact build.

- `/tim icons`: every one of the 43 identities and families rendered its intended
  icon. None fell back.
- The Coins texture path (`Interface\Icons\INV_Misc_Coin_01`) exists and renders.
- In the main window, the coin icons on funds and prices rendered (copper, silver
  and gold), and the row icons showed beside their labels.
- One overlap: the Gold Power Core and the 9-60 Battery Pack items share one icon in
  the client.
- Retail icons are in the Forever client too, if an abstract family should ever get
  a more fitting picture.

| Role | Name | Source | Status |
| --- | --- | --- | --- |
| `clips` | Handfuls of Copper Bolts | [item 4359](https://www.wowhead.com/forever/item=4359) | client-verified |
| `wire` | Copper Bars | [item 2840](https://www.wowhead.com/forever/item=2840) | client-verified |
| `autoClippers` | Whirring Bronze Gizmos | [item 4375](https://www.wowhead.com/forever/item=4375) | client-verified |
| `megaClippers` | Thorium Widgets | [item 15994](https://www.wowhead.com/forever/item=15994) | client-verified |
| `processors` | Copper Modulators | [item 4363](https://www.wowhead.com/forever/item=4363) | client-verified |
| `memory` | White Punch Cards | [item 9279](https://www.wowhead.com/forever/item=9279) | client-verified |
| `chips` | Arcane Crystals | [item 12363](https://www.wowhead.com/forever/item=12363) | client-verified |
| `harvesters` | Compact Harvest Reapers | [item 4391](https://www.wowhead.com/forever/item=4391) | client-verified |
| `wireDrones` | Delicate Arcanite Converters | [item 16006](https://www.wowhead.com/forever/item=16006) | client-verified |
| `farms` | Gold Power Cores | [item 10558](https://www.wowhead.com/forever/item=10558) | client-verified |
| `batteries` | 9-60 Battery Packs | [item 274048](https://www.wowhead.com/forever/item=274048) | client-verified |
| `probes` | Arcanite Dragonlings | [item 16022](https://www.wowhead.com/forever/item=16022) | client-verified |
| `mindControl` | Gnomish Mind Control Cap | [item 10726](https://www.wowhead.com/forever/item=10726) | client-verified |
| `expansion` | Dimensional Ripper - Everlook | [item 18984](https://www.wowhead.com/forever/item=18984) | client-verified |

| Family | Source | Projects | Status |
| --- | --- | --- | --- |
| `automation` | Bronze Tube: [item 4371](https://www.wowhead.com/forever/item=4371) | 26 | client-verified |
| `bolts` | Handfuls of Copper Bolts: [item 4359](https://www.wowhead.com/forever/item=4359) | 18 | client-verified |
| `converter` | Delicate Arcanite Converters: [item 16006](https://www.wowhead.com/forever/item=16006) | 41, 44 | client-verified |
| `copper` | Copper Bars: [item 2840](https://www.wowhead.com/forever/item=2840) | 7, 8, 9, 10, 10b | client-verified |
| `correspondence` | Schematic: Gnomish Universal Remote: [item 7560](https://www.wowhead.com/forever/item=7560) | 2, 13, 140, 141, 142, 143, 144, 145, 146, 147, 148 | client-verified |
| `crystal` | Arcane Crystals: [item 12363](https://www.wowhead.com/forever/item=12363) | 50, 51, 214 | client-verified |
| `dragonling` | Arcanite Dragonlings: [item 16022](https://www.wowhead.com/forever/item=16022) | 210 | client-verified |
| `enforcement` | Goblin Mortar: [item 10577](https://www.wowhead.com/forever/item=10577) | 29, 131 | client-verified |
| `expansion` | Dimensional Ripper - Everlook: [item 18984](https://www.wowhead.com/forever/item=18984) | 46, 200, 201 | client-verified |
| `fleet` | Goblin Jumper Cables XL: [item 18587](https://www.wowhead.com/forever/item=18587) | 110, 111, 112 | client-verified |
| `foresight` | Ornate Spyglass: [item 5507](https://www.wowhead.com/forever/item=5507) | 19, 27, 119 | client-verified |
| `foundry` | Blacksmithing: [spell 2018](https://www.wowhead.com/forever/spell=2018) | 45, 100, 101, 102, 212 | client-verified |
| `gizmo` | Whirring Bronze Gizmos: [item 4375](https://www.wowhead.com/forever/item=4375) | 1, 4, 5 | client-verified |
| `hull` | Mithril Casing: [item 10561](https://www.wowhead.com/forever/item=10561) | 129 | client-verified |
| `mindControl` | Gnomish Mind Control Cap: [item 10726](https://www.wowhead.com/forever/item=10726) | 34, 70, 35 | client-verified |
| `modulator` | Copper Modulators: [item 4363](https://www.wowhead.com/forever/item=4363) | 215, 219 | client-verified |
| `money` | texture `Interface\Icons\INV_Misc_Coin_01` | 21, 37, 38, 42, 40, 40b | client-verified |
| `negotiation` | Gnomish Universal Remote: [item 7506](https://www.wowhead.com/forever/item=7506) | 20, 60, 61, 62, 63, 64, 65, 66, 118, 128, 213 | client-verified |
| `network` | Truesilver Transformer: [item 18631](https://www.wowhead.com/forever/item=18631) | 126, 130, 132, 211 | client-verified |
| `power` | Gold Power Cores: [item 10558](https://www.wowhead.com/forever/item=10558) | 125, 127 | client-verified |
| `precision` | Gyrochronatom: [item 4389](https://www.wowhead.com/forever/item=4389) | 15, 17, 16, 217 | client-verified |
| `punchCard` | White Punch Cards: [item 9279](https://www.wowhead.com/forever/item=9279) | 135, 216 | client-verified |
| `reaper` | Compact Harvest Reapers: [item 4391](https://www.wowhead.com/forever/item=4391) | 43 | client-verified |
| `remedy` | Alchemy: [spell 2259](https://www.wowhead.com/forever/spell=2259) | 28, 31 | client-verified |
| `speed` | Goblin Rocket Fuel: [item 9061](https://www.wowhead.com/forever/item=9061) | 120 | client-verified |
| `tinkering` | Arclight Spanner: [item 6219](https://www.wowhead.com/forever/item=6219) | 3 | client-verified |
| `weather` | World Enlarger: [item 18660](https://www.wowhead.com/forever/item=18660) | 30 | client-verified |
| `widget` | Thorium Widgets: [item 15994](https://www.wowhead.com/forever/item=15994) | 22, 23, 24, 25 | client-verified |
| `writing` | Goblin Rocket Fuel Recipe: [item 10644](https://www.wowhead.com/forever/item=10644) | 6, 11, 12, 14, 121, 133, 134, 218 | client-verified |
