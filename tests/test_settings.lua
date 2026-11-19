-- Help and settings (#23): the first-use help with the brief's persistence wording,
-- settings saved with the account and checked on load, and none of it touching the
-- simulation.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load({ firstUse = true })
local h = Harness.Helpers(captured)
local Settings, Host, Window = ns.Settings, ns.Host, ns.Window

-- Defaults, and damaged saved values ignored one by one (never a blocked save).
local v = Settings.Load(nil)
check(v.model and v.voice and v.scale == 1 and not v.helpSeen and v.point == nil)
v = Settings.Load({ model = "yes", voice = false, scale = 9, helpSeen = true, point = { "NOWHERE", "TOP", 1, 2 }, extra = 1 })
check(v.model == true and v.voice == false and v.scale == 1 and v.helpSeen == true and v.point == nil)
v = Settings.Load({ scale = 0 / 0 })
check(v.scale == 1, "NaN is not a scale")
v = Settings.Load({ scale = 1.2, point = { "TOPLEFT", "TOPLEFT", 40, -60 } })
check(v.scale == 1.2 and v.point[1] == "TOPLEFT" and v.point[3] == 40)
Settings.Load(nil)

-- First use: /tim start opens the help once, with the brief's exact persistence text.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
check(Window.help and Window.help:IsShown(), "the first company shows the help")
check(h.shownText("Progress is saved when you log out normally or reload the interface. A crash or forced close "
    .. "can lose progress since the last successful save. After a long session, use /reload when it is safe to do so."))
check(Settings.values.helpSeen)
-- Short sections in order, the controls one per line (#80).
check(Window.help.title._text == "Time Is Money: Help")
local headings = {}
for i, section in ipairs(Window.help.sections) do headings[i] = section.heading._text end
check(table.concat(headings, "|") == "Getting started|Controls|Saving progress|Credits")
check(h.shownText("a game by Frank Lantz") and h.shownText("decisionproblem.com/paperclips"), "the original credited")
local controls = Window.help.sections[2].lines
check(#controls == #Window.HELP_SECTIONS[2].lines and #controls == 8)
for i, fs in ipairs(controls) do
    check(fs._text:find("^/tim") and fs._text ~= Window.HELP_SECTIONS[2].lines[i], "a translated command line")
end
-- /tim help prints the same lines in chat.
local before = #captured.messages
env.SlashCmdList.TIMEISMONEY("help")
local printed = {}
for i = before + 1, #captured.messages do printed[#printed + 1] = captured.messages[i] end
check(table.concat(printed, "\n"):find(controls[3]._text, 1, true), "chat and panel share the lines")
-- Each line sits below the previous one.
local last = 0
for _, section in ipairs(Window.help.sections) do
    for _, fs in ipairs({ section.heading, unpack(section.lines) }) do
        check(h.point(fs)[5] < last, "stacked downwards")
        last = h.point(fs)[5]
    end
end
Window.help:Hide()
check(Host.newGame())
Window.Refresh()
check(not Window.help:IsShown(), "only once")
-- /tim help shows it again any time.
env.SlashCmdList.TIMEISMONEY("help")
check(Window.help:IsShown())
Window.help:Hide()

-- The settings panel: model, voice, scale, help and the new game.
game = Host.game
local snapshot = h.digest(game.S)
local draws = Host.random.count
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
-- The portrait selector lights the current choice; the greeting is a checkbox.
check(p:IsShown() and p.modelOn.label._text == "Animated" and p.modelOff.label._text == "Portrait")
check(p.voice.check._shown and p.voiceLabel._text == "Gazlowe's voice")
check(p.reportSound.check._shown and p.reportSoundLabel._text == "Sound for new reports")
p.modelOff._scripts.OnClick(p.modelOff)
check(not Settings.values.model and ns.Director.state == "portrait")
p.modelOff._scripts.OnClick(p.modelOff)
check(not Settings.values.model, "choosing the current option keeps it")
p.voice._scripts.OnClick(p.voice)
check(not Settings.values.voice and not p.voice.check._shown, "the checkbox clears")
local played = #captured.sounds
Window.Toggle()
Window.Toggle()
check(#captured.sounds == played, "no greeting with the voice off")
p.larger._scripts.OnClick(p.larger)
check(Settings.values.scale == 1.1 and p.scaleLabel._text == "Window scale: 110%")
for _ = 1, 10 do p.larger._scripts.OnClick(p.larger) end
check(Settings.values.scale == 1.5, "the scale stops at its bound")
Window.Refresh()
check(Window.frame._scale <= 1.5)
p.smaller._scripts.OnClick(p.smaller)
check(Settings.values.scale == 1.4)
-- None of it touched the company.
check(h.digest(game.S) == snapshot and Host.random.count == draws, "settings never touch the simulation")
-- New game from the settings: behind the confirmation, which comes in front of the
-- settings panel (a stratum above it, and raised) (Codex review of #69).
p.newGame._scripts.OnClick(p.newGame)
check(Window.dialog:IsShown() and Window.dialog.question._text:find("Start a new company?", 1, true))
check(captured.raised == Window.dialog and Window.dialog._strata == "FULLSCREEN_DIALOG" and p._strata == "DIALOG",
    "the confirmation is in front of the settings")
Window.dialog.no._scripts.OnClick(Window.dialog.no)
check(Host.game == game)

-- The window's position is kept when dragged, as its top-left corner in UIParent
-- units, and the window is placed back there at whatever scale it has.
local f = Window.frame
f._left, f._top, f._scale = 100, 500, 1.2 -- the frame's own (scaled) coordinates
f._scripts.OnDragStop(f)
local point = Settings.values.point
check(point[1] == "TOPLEFT" and point[2] == "BOTTOMLEFT" and math.abs(point[3] - 120) < 1e-9
    and math.abs(point[4] - 600) < 1e-9, "screen units: offsets times the scale")
check(h.point(f)[1] == "TOPLEFT" and math.abs(h.point(f)[4] - 100) < 1e-9 and math.abs(h.point(f)[5] - 500) < 1e-9)
-- A scale change keeps the corner on screen where it was (offsets divided by it).
f._scale = 1.5
Window.PlaceWindow()
check(math.abs(h.point(f)[4] * 1.5 - 120) < 1e-9 and math.abs(h.point(f)[5] * 1.5 - 600) < 1e-9)
-- Redraws do not re-anchor at an unchanged scale (a drag in progress is left alone).
f._points = {}
Window.Refresh()
check(h.point(f) == nil or f._scale ~= 1.5, "no re-anchoring on every redraw")
-- Help opened from the settings comes to the front.
p.helpButton._scripts.OnClick(p.helpButton)
check(captured.raised == Window.help, "help in front of the settings")
Window.help:Hide()
-- /tim model refreshes an open settings panel.
env.SlashCmdList.TIMEISMONEY("model")
check(Settings.values.model and p.modelOn.check._shown and not p.modelOff.check._shown, "the panel follows /tim model")

-- Logout writes the settings with the company; a reload reads them back.
local db = Host.persist()
check(db.settings and db.settings.model == true and db.settings.scale == 1.4 and math.abs(db.settings.point[4] - 600) < 1e-9)
check(db.company, "the company is saved too")
local env2, captured2, ns2 = Harness.Load({ firstUse = true })
ns2.Host.loadSaved(db)
ns2.Settings.Load(ns2.Host.savedSettings)
check(ns2.Settings.values.model == true and ns2.Settings.values.scale == 1.4 and ns2.Settings.values.helpSeen)
ns2.Window.Toggle()
local at = h.point(ns2.Window.frame)
local scale2 = ns2.Window.frame._scale
check(at[1] == "TOPLEFT" and at[3] == "BOTTOMLEFT" and math.abs(at[4] * scale2 - 120) < 1e-9
    and math.abs(at[5] * scale2 - 600) < 1e-9, "the window opens where it was left")
-- While saving is off, the settings say their changes are not kept.
local env4, captured4, ns4 = Harness.Load()
ns4.Host.loadSaved({ schema = 999 })
env4.SlashCmdList.TIMEISMONEY("settings")
check(ns4.Window.settings.notice._shown and ns4.Window.settings.notice._text:find("not kept", 1, true))
-- NaN is never a valid setting (JSMath.isNaN: in WoW's Lua NaN compares true).
check(ns.Settings.Load({ scale = 0 / 0, point = { "TOPLEFT", "BOTTOMLEFT", 0 / 0, 1 } }).point == nil)
ns.Settings.Load(db.settings)

-- Settings alone are written even before any company exists.
local env3, captured3, ns3 = Harness.Load()
ns3.Settings.Set("voice", false)
local onlySettings = ns3.Host.persist()
check(onlySettings and onlySettings.settings.voice == false and onlySettings.company == nil)

eq(h.acceptKnownStrays(), 2, "the known stray help line, once per /tim help (#114)")

-- Covered: defaults, damaged values, first-use help, persistence wording, panel, scale, position, saving and no simulation effect.
done(libGlass and "test_settings (real LibGlass)" or "test_settings (LibGlass stand-in)")
