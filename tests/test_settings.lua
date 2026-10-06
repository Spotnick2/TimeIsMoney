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
assert(p:IsShown() and p.model.label.text == "Director: animated model" and p.voice.label.text == "Director's greeting: on")
p.model.scripts.OnClick(p.model)
assert(not Settings.values.model and p.model.label.text == "Director: portrait" and ns.Director.state == "portrait")
p.voice.scripts.OnClick(p.voice)
assert(not Settings.values.voice)
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
-- New game from the settings: behind the confirmation.
p.newGame.scripts.OnClick(p.newGame)
assert(Window.dialog:IsShown() and Window.dialog.question.text:find("Start a new company?", 1, true))
Window.dialog.no.scripts.OnClick(Window.dialog.no)
assert(Host.game == game)

-- The window's position is kept when dragged, and restored next time.
Window.frame.GetPoint = function() return "TOPLEFT", env.UIParent, "TOPLEFT", 120, -80 end
Window.frame.scripts.OnDragStop(Window.frame)
assert(Settings.values.point[1] == "TOPLEFT" and Settings.values.point[3] == 120)

-- Logout writes the settings with the company; a reload reads them back.
local db = Host.persist()
assert(db.settings and db.settings.model == false and db.settings.scale == 1.4 and db.settings.point[4] == -80)
assert(db.company, "the company is saved too")
local env2, captured2, ns2 = Harness.Load({ firstUse = true })
ns2.Host.loadSaved(db)
ns2.Settings.Load(ns2.Host.savedSettings)
assert(ns2.Settings.values.model == false and ns2.Settings.values.scale == 1.4 and ns2.Settings.values.helpSeen)
ns2.Window.Toggle()
local at = ns2.Window.frame.point
assert(at[1] == "TOPLEFT" and at[3] == "TOPLEFT" and at[4] == 120 and at[5] == -80, "the window opens where it was left")
-- Settings alone are written even before any company exists.
local env3, captured3, ns3 = Harness.Load()
ns3.Settings.Set("voice", false)
local onlySettings = ns3.Host.persist()
assert(onlySettings and onlySettings.settings.voice == false and onlySettings.company == nil)

print((libGlass and "settings (real LibGlass)" or "settings (LibGlass stand-in)")
    .. ": defaults, damaged values, first-use help, persistence wording, panel, scale, position, saving and no simulation effect passed")
