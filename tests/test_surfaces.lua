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
local S = Host.game.S
S.funds, S.wire = 0, 1000
Host.update(0.02)
Window.Refresh()
local buy = assert(h.button("btnMakeClipper") or h.button("btnBuyWire"), "a purchase button shows")
assert(not buy:IsEnabled() and buy.glass.surfaceEnabled == false and buy.glass.surfaceTint == nil)
assert(make:IsEnabled() and make.glass.surfaceTint, "the accent returns with the bars")
-- Panels: nearly opaque.
Window.ShowHelp()
assert(Window.help.glass.surfaceTint and Window.help.glass.surfaceTint[4] >= 0.9, "help is nearly opaque")
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
assert(p.glass.surfaceTint[4] >= 0.9, "settings is nearly opaque")
-- The portrait choice: the current one lit, the other plain.
assert(p.modelOn.glass.surfaceTint and p.modelOff.glass.surfaceTint == nil)
assert(p.modelOn.check.shown and not p.modelOff.check.shown, "and checked, not by colour alone")
-- Choosing the current option reloads nothing.
local loads = captured.modelLoads or 0
p.modelOn.scripts.OnClick(p.modelOn)
assert((captured.modelLoads or 0) == loads, "no model reload")
p.modelOff.scripts.OnClick(p.modelOff)
assert(p.modelOff.glass.surfaceTint and p.modelOn.glass.surfaceTint == nil and p.modelOff.check.shown)
-- Surface calls happen only on a change of state, not on every redraw.
local calls = 0
local glass = env.LibStub("LibGlass-1.0"):New()
local set = glass.SetSurfaceEnabled
glass.SetSurfaceEnabled = function(...) calls = calls + 1 return set(...) end
Window.Refresh()
Window.Refresh()
glass.SetSurfaceEnabled = set
assert(calls == 0, "no surface calls without a change: " .. calls)
-- The settings button shows a cog, not "=".
local cog = false
for _, t in ipairs(captured.textures) do if t.texture == Window.SETTINGS_ICON then cog = true end end
assert(cog, "the settings cog")

print("surfaces (LibGlass stand-in): thin rims, the primary accent, dimmed unavailable buttons, opaque panels, portrait choice and cog passed")
