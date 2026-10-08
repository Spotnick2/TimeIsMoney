-- Help and settings (#23): the first-use help with the brief's persistence wording,
-- settings saved with the account and checked on load, and none of it touching the
-- simulation.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load({ firstUse = true })
local h = Harness.Helpers(captured)
local Settings, Host, Window = ns.Settings, ns.Host, ns.Window

-- Defaults, and damaged saved values ignored one by one (never a blocked save).
local v = Settings.Load(nil)
assert(v.model and v.voice and v.scale == 1 and not v.helpSeen and v.point == nil)
v = Settings.Load({ model = "yes", voice = false, scale = 9, helpSeen = true, point = { "NOWHERE", "TOP", 1, 2 }, extra = 1 })
assert(v.model == true and v.voice == false and v.scale == 1 and v.helpSeen == true and v.point == nil)
v = Settings.Load({ scale = 0 / 0 })
assert(v.scale == 1, "NaN is not a scale")
v = Settings.Load({ scale = 1.2, point = { "TOPLEFT", "TOPLEFT", 40, -60 } })
assert(v.scale == 1.2 and v.point[1] == "TOPLEFT" and v.point[3] == 40)
Settings.Load(nil)

-- First use: /tim start opens the help once, with the brief's exact persistence text.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
assert(Window.help and Window.help:IsShown(), "the first company shows the help")
assert(h.shownText("Progress is saved when you log out normally or reload the interface. A crash or forced close "
    .. "can lose progress since the last successful save. After a long session, use /reload when it is safe to do so."))
assert(Settings.values.helpSeen)
Window.help:Hide()
assert(Host.newGame())
Window.Refresh()
assert(not Window.help:IsShown(), "only once")
-- /tim help shows it again any time.
env.SlashCmdList.TIMEISMONEY("help")
assert(Window.help:IsShown())
Window.help:Hide()

-- The settings panel: model, voice, scale, help and the new game.
game = Host.game
local snapshot = h.digest(game.S)
local draws = Host.random.count
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
-- The portrait selector lights the current choice; the greeting is a checkbox.
assert(p:IsShown() and p.modelOn.label.text == "Animated" and p.modelOff.label.text == "Portrait")
assert(p.voice.check.shown and p.voiceLabel.text == "Play Gazlowe's greeting")
p.modelOff.scripts.OnClick(p.modelOff)
assert(not Settings.values.model and ns.Director.state == "portrait")
p.modelOff.scripts.OnClick(p.modelOff)
assert(not Settings.values.model, "choosing the current option keeps it")
p.voice.scripts.OnClick(p.voice)
assert(not Settings.values.voice and not p.voice.check.shown, "the checkbox clears")
local played = #captured.sounds
Window.Toggle()
Window.Toggle()
assert(#captured.sounds == played, "no greeting with the voice off")
p.larger.scripts.OnClick(p.larger)
assert(Settings.values.scale == 1.1 and p.scaleLabel.text == "Window scale: 110%")
for _ = 1, 10 do p.larger.scripts.OnClick(p.larger) end
assert(Settings.values.scale == 1.5, "the scale stops at its bound")
Window.Refresh()
assert(Window.frame.scale <= 1.5)
p.smaller.scripts.OnClick(p.smaller)
assert(Settings.values.scale == 1.4)
-- None of it touched the company.
assert(h.digest(game.S) == snapshot and Host.random.count == draws, "settings never touch the simulation")
-- New game from the settings: behind the confirmation, which comes in front of the
-- settings panel (a stratum above it, and raised) (Codex review of #69).
p.newGame.scripts.OnClick(p.newGame)
assert(Window.dialog:IsShown() and Window.dialog.question.text:find("Start a new company?", 1, true))
assert(captured.raised == Window.dialog and Window.dialog.strata == "FULLSCREEN_DIALOG" and p.strata == "DIALOG",
    "the confirmation is in front of the settings")
Window.dialog.no.scripts.OnClick(Window.dialog.no)
assert(Host.game == game)

-- The window's position is kept when dragged, as its top-left corner in UIParent
-- units, and the window is placed back there at whatever scale it has.
local f = Window.frame
f.left, f.top, f.scale = 100, 500, 1.2 -- the frame's own (scaled) coordinates
f.scripts.OnDragStop(f)
local point = Settings.values.point
assert(point[1] == "TOPLEFT" and point[2] == "BOTTOMLEFT" and math.abs(point[3] - 120) < 1e-9
    and math.abs(point[4] - 600) < 1e-9, "screen units: offsets times the scale")
assert(f.point[1] == "TOPLEFT" and math.abs(f.point[4] - 100) < 1e-9 and math.abs(f.point[5] - 500) < 1e-9)
-- A scale change keeps the corner on screen where it was (offsets divided by it).
f.scale = 1.5
Window.PlaceWindow()
assert(math.abs(f.point[4] * 1.5 - 120) < 1e-9 and math.abs(f.point[5] * 1.5 - 600) < 1e-9)
-- Redraws do not re-anchor at an unchanged scale (a drag in progress is left alone).
f.point = nil
Window.Refresh()
assert(f.point == nil or f.scale ~= 1.5, "no re-anchoring on every redraw")
-- Help opened from the settings comes to the front.
p.helpButton.scripts.OnClick(p.helpButton)
assert(captured.raised == Window.help, "help in front of the settings")
Window.help:Hide()
-- /tim model refreshes an open settings panel.
env.SlashCmdList.TIMEISMONEY("model")
assert(Settings.values.model and p.modelOn.check.shown and not p.modelOff.check.shown, "the panel follows /tim model")

-- Logout writes the settings with the company; a reload reads them back.
local db = Host.persist()
assert(db.settings and db.settings.model == true and db.settings.scale == 1.4 and math.abs(db.settings.point[4] - 600) < 1e-9)
assert(db.company, "the company is saved too")
local env2, captured2, ns2 = Harness.Load({ firstUse = true })
ns2.Host.loadSaved(db)
ns2.Settings.Load(ns2.Host.savedSettings)
assert(ns2.Settings.values.model == true and ns2.Settings.values.scale == 1.4 and ns2.Settings.values.helpSeen)
ns2.Window.Toggle()
local at = ns2.Window.frame.point
local scale2 = ns2.Window.frame.scale
assert(at[1] == "TOPLEFT" and at[3] == "BOTTOMLEFT" and math.abs(at[4] * scale2 - 120) < 1e-9
    and math.abs(at[5] * scale2 - 600) < 1e-9, "the window opens where it was left")
-- While saving is off, the settings say their changes are not kept.
local env4, captured4, ns4 = Harness.Load()
ns4.Host.loadSaved({ schema = 999 })
env4.SlashCmdList.TIMEISMONEY("settings")
assert(ns4.Window.settings.notice.shown and ns4.Window.settings.notice.text:find("not kept", 1, true))
-- NaN is never a valid setting (JSMath.isNaN: in WoW's Lua NaN compares true).
assert(ns.Settings.Load({ scale = 0 / 0, point = { "TOPLEFT", "BOTTOMLEFT", 0 / 0, 1 } }).point == nil)
ns.Settings.Load(db.settings)

-- Settings alone are written even before any company exists.
local env3, captured3, ns3 = Harness.Load()
ns3.Settings.Set("voice", false)
local onlySettings = ns3.Host.persist()
assert(onlySettings and onlySettings.settings.voice == false and onlySettings.company == nil)

print((libGlass and "settings (real LibGlass)" or "settings (LibGlass stand-in)")
    .. ": defaults, damaged values, first-use help, persistence wording, panel, scale, position, saving and no simulation effect passed")
