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
- Talk, approval and reaction animations are still unidentified: idle only until
  measured. Do not guess IDs from Retail animation lists.

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
  no reaction animations until they are measured.
  - It uses the measured recipe above: camera at +40 on X facing back, field of
    view 0.15, clip 0.1-100, centred origin, particles at scale 0.
  - It is framed from the live box on the 0.40 crop with a 1.15 margin. The offset
    is divided by the scale, because the client scales the actor's position.
- **Loading:** the model loads once per appearance. Its box is polled every 0.1 s,
  at most 30 times, by `C_Timer.After`. A token drops late answers on hide (the
  strip's OnHide), on a speaker change, or on a toggle.
  - With no box, or a failed `SetModelByCreatureDisplayID`, it shows the 2D
    portrait from the same display for the rest of the session, with no retry per
    redraw.
- **`/tim model`** switches between the live model and the portrait. This session
  only; saving it is a setting (#23).
- **Speakers:** from `UI/Dialogue.lua`, a pure function of the saved state.
  - The Director speaks in phase I.
  - After the takeover the model is cleared, and the Ledger's reports show the
    company mark (the bolts icon).
  - The Unlisted Director's letters show a dragonling.
- **No cosmetic effect on the game:** no randomness, no game state, no logical
  timers. A test redraws repeatedly and checks the state and draw count are
  unchanged.

To check in the client:
- readability at the strip's real size and at several UI scales;
- crop and clipping inside the glass;
- the idle animation;
- hide/show repeatedly, and phase changes;
- frame time.
