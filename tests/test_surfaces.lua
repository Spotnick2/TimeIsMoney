-- The window's glass surfaces (LibGlass r3, UX critique): thin rims on cards and
-- buttons, nearly opaque panels, the primary action's accent only while usable,
-- and a dimmed surface for every unavailable button. Recorded through the
-- stand-in, which keeps each surface's calls (stubs cannot prove pixels).
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load({ standIn = true })
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

env.SlashCmdList.TIMEISMONEY("start")
local make = h.button("btnMakePaperclip")
assert(make.glass.size == "thin_small", "buttons take the thin rim")
assert(make:IsEnabled() and make.glass.surfaceEnabled == true and make.glass.surfaceTint, "the primary accent while usable")
-- Unavailable: the accent goes and the surface dims.
Host.game.S.wire = 0
Host.update(0.02)
Window.Refresh()
assert(not make:IsEnabled() and make.glass.surfaceEnabled == false and make.glass.surfaceTint == nil)
-- Any other unavailable button dims without an accent.
local campaign = h.button("btnExpandMarketing")
if campaign and not campaign:IsEnabled() then
    assert(campaign.glass.surfaceEnabled == false and campaign.glass.surfaceTint == nil)
end
-- Panels: nearly opaque.
Window.ShowHelp()
assert(Window.help.glass.surfaceTint and Window.help.glass.surfaceTint[4] >= 0.9, "help is nearly opaque")
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
assert(p.glass.surfaceTint[4] >= 0.9, "settings is nearly opaque")
-- The portrait choice: the current one lit, the other plain.
assert(p.modelOn.glass.surfaceTint and p.modelOff.glass.surfaceTint == nil)
p.modelOff.scripts.OnClick(p.modelOff)
assert(p.modelOff.glass.surfaceTint and p.modelOn.glass.surfaceTint == nil)
-- The settings button shows a cog, not "=".
local cog = false
for _, t in ipairs(captured.textures) do if t.texture == Window.SETTINGS_ICON then cog = true end end
assert(cog, "the settings cog")

print("surfaces (LibGlass stand-in): thin rims, the primary accent, dimmed unavailable buttons, opaque panels, portrait choice and cog passed")
