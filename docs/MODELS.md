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

[#10](https://github.com/Spotnick2/TimeIsMoney/issues/10) probes existing Forever goblin
creature displays. No goblin display/emote IDs are selected or tested here.
Record display/provenance/build, textured rendering, framing/idle motion and useful
talk/approval/reaction animations. Do not guess IDs from Retail animation lists.

[#22](https://github.com/Spotnick2/TimeIsMoney/issues/22) integrates one reused Director
scene, idle by default, measured reactions only. Cosmetics cannot delay commands,
consume simulation RNG or affect logical timers. The Director disappears after
takeover, and the company mark/reports replace him according to the brief.
Use a verified 2D/text fallback and model toggle. Hiding cancels model callbacks
while simulation continues.

Test real strip size/UI scales, texture/crop/clipping, late/missing display, emotes,
particles, mouse input, repeated open/close/phase changes and frame time.
Record observations in forever-api-notes.md before making measured claims.
