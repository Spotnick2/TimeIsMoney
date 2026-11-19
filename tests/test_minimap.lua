-- The minimap button (#78): Gazlowe's portrait on a glass disc at the minimap's
-- edge; left click the ledger, right click the settings; dragged around the edge,
-- its angle saved; hidden on request. It never changes the company.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window, Settings, MB = ns.Host, ns.Window, ns.Settings, ns.MinimapButton

local b = assert(MB.button, "built at load")
check(b._parent == env.Minimap and b._shown and b._width == 32 and b._height == 32)
check(b.icon.portraitDisplay == 7052, "Gazlowe's portrait")
local function near(a, x) return math.abs(a - x) < 1e-6 end
-- The default place: lower left, on the edge (radius 70 + 10).
local p = h.point(b)
check(p[1] == "CENTER" and p[2] == env.Minimap and near(p[4], 80 * math.cos(math.rad(225))) and near(p[5], 80 * math.sin(math.rad(225))))

-- Tooltip: the company's state and both clicks.
local function tip()
    b._scripts.OnEnter(b)
    local lines = env.GameTooltip.lines
    b._scripts.OnLeave(b)
    return table.concat(lines, "|")
end
check(tip():find("No company yet", 1, true) and tip():find("Left-click", 1, true) and tip():find("Right-click", 1, true))

-- Left click with no company: says how to start (as /tim); right click: settings.
b._scripts.OnClick(b, "LeftButton")
check(captured.messages[#captured.messages]:find("No company yet", 1, true))
b._scripts.OnClick(b, "RightButton")
check(Window.settings and Window.settings:IsShown(), "right click opens the settings")
b._scripts.OnClick(b, "RightButton")
check(not Window.settings:IsShown(), "and closes them")

-- With a company: left click opens and closes the ledger; the tooltip follows.
env.SlashCmdList.TIMEISMONEY("start")
Window.frame:Hide()
local snapshot, draws = h.digest(Host.game.S), Host.random.count
b._scripts.OnClick(b, "LeftButton")
check(Window.frame:IsShown(), "left click opens the ledger")
b._scripts.OnClick(b, "LeftButton")
check(not Window.frame:IsShown(), "and closes it")
check(tip():find("running", 1, true))
check(Host.setPaused(true))
check(tip():find("paused", 1, true))
check(Host.setPaused(false))
check(h.digest(Host.game.S) == snapshot and Host.random.count == draws, "the button never changes the company")

-- Drag: follows the cursor around the edge; the angle is saved on release.
b._scripts.OnDragStart(b)
WoW.cursorX, WoW.cursorY = 500, 480 -- straight above the centre: 90 degrees
b._scripts.OnUpdate(b, 0.02)
check(near(h.point(b)[4], 0) and near(h.point(b)[5], 80), "placed while dragging")
WoW.cursorX, WoW.cursorY = 580, 400 -- east: 0 degrees
b._scripts.OnDragStop(b)
check(b._scripts.OnUpdate == nil and near(Settings.values.minimapAngle, 0) and near(h.point(b)[4], 80))
check(Settings.Data().minimapAngle == Settings.values.minimapAngle, "saved with the settings")

-- Hidden on request (/tim minimap and the settings checkbox), and back.
env.SlashCmdList.TIMEISMONEY("minimap")
check(not b._shown and Settings.values.minimap == false and Settings.Data().minimap == false)
env.SlashCmdList.TIMEISMONEY("settings")
local panel = Window.settings
check(not panel.minimap.check._shown and panel.minimapLabel._text == "Show the minimap button")
panel.minimap._scripts.OnClick(panel.minimap)
check(b._shown and panel.minimap.check._shown, "the checkbox shows it again")

-- Damaged saved values fall back to the defaults.
local values = Settings.Load({ minimap = "yes", minimapAngle = 0 / 0 })
check(values.minimap == true and values.minimapAngle == 225)
values = Settings.Load({ minimapAngle = 400 })
check(values.minimapAngle == 225)
values = Settings.Load({ minimap = false, minimapAngle = 12.5 })
check(values.minimap == false and values.minimapAngle == 12.5)

-- Saving off (unrecognized data): the tooltip never suggests /tim start.
local env2, captured2, ns2 = Harness.Load()
ns2.Host.loadSaved({ schema = 999 })
local b2 = ns2.MinimapButton.button
b2._scripts.OnEnter(b2)
local said = table.concat(env2.GameTooltip.lines, "|")
check(said:find("Saving is off", 1, true) and not said:find("/tim start", 1, true))

-- Covered: portrait on the edge, clicks, tooltip state, drag and saved angle, hiding, damaged values and no simulation effect.
done("test_minimap")
