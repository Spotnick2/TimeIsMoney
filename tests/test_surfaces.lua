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
-- One button system (#89): no accent at rest; brighter on hover, darker while
-- pressed; unavailable dims and takes no hover highlight.
assert(make:IsEnabled() and make.glass.surfaceEnabled == true and make.glass.surfaceTint == nil, "plain glass at rest")
make.scripts.OnEnter(make)
assert(make.glass.surfaceTint and make.glass.surfaceTint[4] == Window.HOVER_TINT[4], "hover brightens")
make.scripts.OnMouseDown(make)
assert(make.glass.surfaceTint[4] == Window.PRESSED_TINT[4], "pressed darkens")
make.scripts.OnMouseUp(make)
assert(make.glass.surfaceTint[4] == Window.HOVER_TINT[4], "back to hover on release")
make.scripts.OnLeave(make)
assert(make.glass.surfaceTint == nil, "plain again")
-- Unavailable: dims, and no hover highlight.
Host.game.S.wire = 0
Host.update(0.02)
Window.Refresh()
assert(not make:IsEnabled() and make.glass.surfaceEnabled == false and make.glass.surfaceTint == nil)
make.scripts.OnEnter(make)
assert(make.glass.surfaceTint == nil, "no hover highlight while unavailable")
make.scripts.OnLeave(make)
-- Any other unavailable button dims the same way.
local S = Host.game.S
S.funds, S.wire = 0, 1000
Host.update(0.02)
Window.Refresh()
local buy = assert(h.button("btnMakeClipper") or h.button("btnBuyWire"), "a purchase button shows")
assert(not buy:IsEnabled() and buy.glass.surfaceEnabled == false and buy.glass.surfaceTint == nil)
assert(make:IsEnabled() and make.glass.surfaceTint == nil, "Make is a plain available button again")
-- The main window: darker than the bare glass, lighter than the panels (#80).
-- The bare material's alpha from the real library when it is available (the
-- stand-in has no STYLE).
local envReal = Harness.Load()
local real = envReal.LibStub("LibGlass-1.0"):New()
local bare = real.STYLE and real.STYLE.tint[4] or 0.24
local main = Window.frame.glass.surfaceTint
assert(main and main[4] > bare and main[4] < Window.PANEL_TINT[4], "the window body is darker, the panels darker still")
-- No "(not yet)" on any button: the dimmed surface and the tooltip carry it (#80).
for _, w in ipairs(captured.widgets) do
    if w.kind == "Button" and w.label and w.label.text then
        assert(not tostring(w.label.text):find("not yet", 1, true), "no (not yet): " .. tostring(w.label.text))
    end
end
-- Every visible unavailable button says why in its tooltip (no word on the label).
local checked = 0
for _, w in ipairs(captured.widgets) do
    if w.kind == "Button" and h.visible(w) and w.enabled == false and w.scripts.OnEnter then
        w.scripts.OnEnter(w)
        local lines = env.GameTooltip.lines or {}
        assert(#lines >= 2, "a reason for " .. tostring(w.label and w.label.text))
        w.scripts.OnLeave(w)
        checked = checked + 1
    end
end
assert(checked > 0, "some buttons are unavailable here")
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
