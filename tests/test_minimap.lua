-- The minimap button (#78): Gazlowe's portrait on a glass disc at the minimap's
-- edge; left click the ledger, right click the settings; dragged around the edge,
-- its angle saved; hidden on request. It never changes the company.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window, Settings, MB = ns.Host, ns.Window, ns.Settings, ns.MinimapButton

local b = assert(MB.button, "built at load")
assert(b.parent == env.Minimap and b.shown and b.width == 32 and b.height == 32)
assert(b.icon.portraitDisplay == 7052, "Gazlowe's portrait")
local function near(a, x) return math.abs(a - x) < 1e-6 end
-- The default place: lower left, on the edge (radius 70 + 10).
local p = b.point
assert(p[1] == "CENTER" and p[2] == env.Minimap and near(p[4], 80 * math.cos(math.rad(225))) and near(p[5], 80 * math.sin(math.rad(225))))

-- Tooltip: the company's state and both clicks.
local function tip()
    b.scripts.OnEnter(b)
    local lines = env.GameTooltip.lines
    b.scripts.OnLeave(b)
    return table.concat(lines, "|")
end
assert(tip():find("No company yet", 1, true) and tip():find("Left-click", 1, true) and tip():find("Right-click", 1, true))

-- Left click with no company: says how to start (as /tim); right click: settings.
b.scripts.OnClick(b, "LeftButton")
assert(captured.messages[#captured.messages]:find("No company yet", 1, true))
b.scripts.OnClick(b, "RightButton")
assert(Window.settings and Window.settings:IsShown(), "right click opens the settings")
b.scripts.OnClick(b, "RightButton")
assert(not Window.settings:IsShown(), "and closes them")

-- With a company: left click opens and closes the ledger; the tooltip follows.
env.SlashCmdList.TIMEISMONEY("start")
Window.frame:Hide()
local snapshot, draws = h.digest(Host.game.S), Host.random.count
b.scripts.OnClick(b, "LeftButton")
assert(Window.frame:IsShown(), "left click opens the ledger")
b.scripts.OnClick(b, "LeftButton")
assert(not Window.frame:IsShown(), "and closes it")
assert(tip():find("running", 1, true))
assert(Host.setPaused(true))
assert(tip():find("paused", 1, true))
assert(Host.setPaused(false))
assert(h.digest(Host.game.S) == snapshot and Host.random.count == draws, "the button never changes the company")

-- Drag: follows the cursor around the edge; the angle is saved on release.
b.scripts.OnDragStart(b)
captured.cursor = { 500, 480 } -- straight above the centre: 90 degrees
b.scripts.OnUpdate(b, 0.02)
assert(near(b.point[4], 0) and near(b.point[5], 80), "placed while dragging")
captured.cursor = { 580, 400 } -- east: 0 degrees
b.scripts.OnDragStop(b)
assert(b.scripts.OnUpdate == nil and near(Settings.values.minimapAngle, 0) and near(b.point[4], 80))
assert(Settings.Data().minimapAngle == Settings.values.minimapAngle, "saved with the settings")

-- Hidden on request (/tim minimap and the settings checkbox), and back.
env.SlashCmdList.TIMEISMONEY("minimap")
assert(not b.shown and Settings.values.minimap == false and Settings.Data().minimap == false)
env.SlashCmdList.TIMEISMONEY("settings")
local panel = Window.settings
assert(not panel.minimap.check.shown and panel.minimapLabel.text == "Show the minimap button")
panel.minimap.scripts.OnClick(panel.minimap)
assert(b.shown and panel.minimap.check.shown, "the checkbox shows it again")

-- Damaged saved values fall back to the defaults.
local values = Settings.Load({ minimap = "yes", minimapAngle = 0 / 0 })
assert(values.minimap == true and values.minimapAngle == 225)
values = Settings.Load({ minimapAngle = 400 })
assert(values.minimapAngle == 225)
values = Settings.Load({ minimap = false, minimapAngle = 12.5 })
assert(values.minimap == false and values.minimapAngle == 12.5)

-- Saving off (unrecognized data): the tooltip never suggests /tim start.
local env2, captured2, ns2 = Harness.Load()
ns2.Host.loadSaved({ schema = 999 })
local b2 = ns2.MinimapButton.button
b2.scripts.OnEnter(b2)
local said = table.concat(env2.GameTooltip.lines, "|")
assert(said:find("Saving is off", 1, true) and not said:find("/tim start", 1, true))

print("minimap: portrait on the edge, clicks, tooltip state, drag and saved angle, hiding, damaged values and no simulation effect passed")
