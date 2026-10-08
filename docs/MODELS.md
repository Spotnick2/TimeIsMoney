# Animated goblin Director

Owner direction (2026-10-02): use AltStable's roster pet model rendering as the
starting point. Preserve a live idle animation. The storyboard portrait is a
visual guide, not the required final raster image.

## Inspected evidence

..\AltStable\Plugins\Roster\AltStableRoster.lua: pet section, specifically PetFrame,
ReadBox, PlacePet, MeasurePet, RenderPets and HidePets.
..\AltStable\docs\forever-api-notes.md: "Pets — a creature renders textured offline",
measured **1.60.1.70124** (issue #75).
Inspected local HEAD: 01708d2a4fedc941b4e9ce5aa4109c2afcde1b24.

- Plain ModelScene + CreateActor + SetModelByCreatureDisplayID; stable preset 718
  lacks the expected pet actor in the measured client.
- Creature display IDs preserve the chosen skin. SetCreature(npcID) can pick a
  random skin. Player races have separate composite-texture limitations; goblin
  humanoid displays still require visual verification.
- Camera on +X, facing back with yaw math.pi, near clip 0.1, far clip 100.
  Narrow FOV 0.15 and distance 40 are the starting recipe, not a proven goblin crop.
- Actor origin centered on all axes, position zero; yaw controls facing.
- GetActiveBoundingBox returns SIX NUMBERS on measured Forever; helper also handles
  two-vector returns. Poll every 0.1 s for a bounded window (~3 s), invalidating
  late callbacks by token when hidden/replaced.
- FOV spans the frame's larger side; fit from box height and leave room for idle.
  AltStable uses height margin 1.3 and width spare 1.4. Its whole-body framing does
  not prove a readable head crop at the dialogue strip's actual size.
- Keep idle animation. Suppress particles initially with SetParticleOverrideScale(0);
  AltStable found particles escaped the frame and inflated the fitted box.
- Scene mouse-disabled with explicit frame levels. Glass masks do not establish
  clipping of models/particles.

## Probe and integration

[#10](https://github.com/Spotnick2/TimeIsMoney/issues/10) measured goblin displays on
1.60.1.70205 (docs/forever-api-notes.md, "#10 goblin model probe"):

- Twelve goblin NPCs' template displays render textured with idle running.
  The targeted unit's own display is unreadable (SetUnit -> 0), and a template can
  answer any of the creature's looks. Pin a look by display ID, checked by eye.
- The 2D fallback is `SetPortraitTextureFromCreatureDisplayID`.
- The actor's position scales with the actor, so offsets are in model units.
- A crop of the top 0.40 of the height with a 1.15 margin frames the 96x72 strip.
- The cost is under 0.5 ms per frame.
- **Talk: animation 60**, picked by the owner on Gazlowe in the client
  (2026-10-08, `/tim anim`). It dips his head; other animations raise it, so the
  scene is taller than the crop (below). Approval and reaction animations are still
  unidentified: do not guess IDs from Retail animation lists.

**Director: Gazlowe, creature display 7052** (npc 3391, Ratchet; owner choice,
2026-10-03). Use the display ID with SetModelByCreatureDisplayID, the 2D portrait
from the same ID as the fallback, and the 0.40 / 1.15 strip crop. Measured box
0.84 x 1.06 x 1.39; #22 still fits from the live box.

[#22](https://github.com/Spotnick2/TimeIsMoney/issues/22) integrates one reused Director
scene, idle by default, measured reactions only. Cosmetics cannot delay commands,
consume simulation RNG or affect logical timers. The Director disappears after
takeover, and the company mark/reports replace him according to the brief.
Use a verified 2D/text fallback and model toggle. Hiding cancels model callbacks
while simulation continues.

Test real strip size/UI scales, texture/crop/clipping, late/missing display, emotes,
particles, mouse input, repeated open/close/phase changes and frame time.
Record observations in forever-api-notes.md before making measured claims.

## Integration (#22)

`UI/Director.lua` puts the Director's strip under the window's cards.

- **Model:** one mouse-disabled ModelScene with Gazlowe, display 7052. Idle runs;
  the report cue plays the talk animation (60) and returns to idle.
  - It uses the measured recipe above: camera at +40 on X facing back, field of
    view 0.15, clip 0.1-100, centred origin, particles at scale 0.
  - It is framed on the 0.40 crop from Gazlowe's **measured height, 1.39**. The
    scene is 136 x 120, taller than the 84 px his margin (1.30) was picked at; the
    margin scales with the height (1.30 x 120 / 84), so his head keeps its size and
    place with room for the talk animation's dip and other animations' rise. The live box follows the idle pose and differs between loads
    (PORTING-TBC-TO-FOREVER, 70205), so it only signals that the model is in. The
    offset is divided by the scale, because the client scales the actor's position.
  - A drift test keeps the box reading and framing equal to the probe's.
- **Loading:** the model loads once per appearance. The window's own redraw polls
  the box every 0.1 s, at most 30 times. The strip has no timers of its own, so a
  hidden window polls nothing, and Host.lua stays the only clock. A token drops the
  poll on hide, on a speaker change, or on a toggle.
  - With no box, or a failed `SetModelByCreatureDisplayID`, it shows the 2D
    portrait from the same display, with no retry per redraw. `/tim model` off and
    on retries.
- **Voice:** opening the window while the Director is speaking plays "Time is
  money, friend!" on the dialog channel, so the player's dialog volume and mute
  apply. The file is 550785, `sound/creature/goblinmalegruffnpc/goblinmalegruffnpcgreeting01.ogg`
  from the community listfile, picked by ear by the owner (2026-10-05).
  - It plays once per opening, never on redraws.
  - Nothing plays after the takeover.
- **`/tim model`** switches between the live model and the portrait. It works
  before the window is opened. This session only; saving it is a setting (#23).
- **Speakers:** from `UI/Dialogue.lua`, a pure function of the saved state.
  - The Director speaks in phase I.
  - After the takeover the model is dropped, and the Ledger's reports show the
    company mark (the bolts icon).
  - The Unlisted Director's letters show a dragonling.
- **The strip's text** belongs to the strip and hides with it. A long line makes
  the strip, and the window, taller.
- **No cosmetic effect on the game:** no randomness, no game state, no logical
  timers. A test redraws repeatedly and checks the state and draw count are
  unchanged.

### Client check — 2026-10-05, 1.60.1.70205 (owner)

- **The live model:** Gazlowe renders textured in the strip. The head-and-shoulders
  crop frames him, and he stays inside the glass.
- **`/tim model`:** shows the round 2D portrait from the same display.
- **Margin:** the model sat on the window's bottom edge, so the bottom margin is now
  10 px.
- **Clipping:** when the idle animation turned Gazlowe's head, it left the 96x72
  scene and was cut at its edge. The scene is now 136x84 with a 1.30 margin. The
  framing recomputes the zoom from the frame, so he keeps his size with room to
  move.

Still to watch over longer play: the idle animation, repeated hide/show and phase
changes, and frame time.
