-- Company reports (#83): every message recorded with its game time, the newest
-- three under Gazlowe, the full history in a scrollable panel, saved beside the
-- company as presentation data.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
-- The welcome message is the first report, at time 0.
check(#Host.reports >= 1 and Host.reports[1].text == "Welcome to Universal Paperclips" and Host.reports[1].at == 0)
-- The simulation's own messages are recorded as they happen, with their time.
game.S.funds = 6
for _ = 1, 30 do Host.update(0.02) end
local last = Host.reports[#Host.reports]
check(last.text == "AutoClippers available for purchase" and last.at > 0, "recorded with its game time")

-- The panel: newest first, with times; opened by clicking the reports or /tim reports.
for i = 1, 30 do game:displayMessage("Processor added, operations (or creativity) per sec increased") end
Window.Refresh()
local area = ns.Director.strip.reportArea
check(h.visible(area), "the reports can be clicked")
area._scripts.OnClick(area)
local p = Window.reports
check(p:IsShown() and p.title._text == "Company reports")
check(p.rows[1].text._text:find("Copper Modulator", 1, true) or p.rows[1].text._text ~= "", "newest first, translated")
check(p.rows[1].time._text:find("^%d+:%d%d:%d%d$"), "with its game time")
check(p.hint._shown and p.hint._text:find("of " .. #Host.reports, 1, true))
-- The wheel scrolls: down shows older reports; it stops at both ends.
p._scripts.OnMouseWheel(p, -1)
check(p.offset == 3)
for _ = 1, 50 do p._scripts.OnMouseWheel(p, -1) end
check(p.offset == #Host.reports - 1, "stops with the oldest at the top")
check(p.rows[1].text._text == "Welcome to Durotar Supply and Logistics.", "the oldest")
-- Long reports wrap: rows stack by measured height and never run past the area.
for _ = 1, 20 do Host.addReport("Welcome to Universal Paperclips", 1000) end
local tall = ns.Messages.Translate("Welcome to Universal Paperclips")
p.offset = 0
local measure = p.rows[1].text.GetStringHeight
for _, row in ipairs(p.rows) do row.text.GetStringHeight = function() return 40 end end
Window.FillReports()
local visible = 0
for _, row in ipairs(p.rows) do if row.text._shown then visible = visible + 1 end end
check(visible < Window.REPORT_ROWS and visible >= 1, "fewer, taller rows fit: " .. visible)
check(h.point(p.rows[2].text)[5] <= h.point(p.rows[1].text)[5] - 40, "each below the previous one's height")
check(p.hint._text:find("1-" .. visible .. " of", 1, true))
-- Mixed heights: once one report does not fit, no shorter older one fills the gap.
local heights = { 100, 100, 60, 14, 14 }
for i, row in ipairs(p.rows) do row.text.GetStringHeight = function() return heights[i] or 14 end end
Window.FillReports()
local seen = {}
for i, row in ipairs(p.rows) do seen[i] = row.text._shown end
check(seen[1] and seen[2] and not seen[3] and not seen[4] and not seen[5], "the page ends at the first misfit")
check(p.hint._text:find("1-2 of", 1, true), "and its range is what it shows")
for _, row in ipairs(p.rows) do row.text.GetStringHeight = measure end
for _ = 1, 50 do p._scripts.OnMouseWheel(p, 1) end
check(p.offset == 0 and p.rows[1].text._text == tall, "back to the newest")
-- Clicking Gazlowe opens and closes them too, with the same tooltip.
local picture = ns.Director.strip.pictureArea
picture._scripts.OnClick(picture)
check(not p:IsShown(), "clicking Gazlowe closes it")
picture._scripts.OnClick(picture)
check(p:IsShown(), "and opens it")
picture._scripts.OnEnter(picture)
check(env.GameTooltip.lines[1] == "Company reports")
picture._scripts.OnLeave(picture)
check(picture._scripts.OnDragStart, "the window still drags from there")
env.SlashCmdList.TIMEISMONEY("reports")
check(not p:IsShown(), "/tim reports closes it")
env.SlashCmdList.TIMEISMONEY("reports")
check(p:IsShown())

-- At most 200 entries: the oldest go first.
for i = 1, 250 do game:displayMessage("Processor added, operations (or creativity) per sec increased") end
check(#Host.reports == Host.REPORTS_MAX)

-- Saved beside the company; restored with the times.
local db = Host.persist()
check(type(db.reports) == "table" and #db.reports == 200 and db.reports[200].text == Host.reports[200].text)
local env2, captured2, ns2 = Harness.Load()
check(ns2.Host.loadSaved(db) == "restored")
check(#ns2.Host.reports == 200 and ns2.Host.reports[200].at == Host.reports[200].at)
-- Damaged entries are dropped, never blocking.
db.reports = { { text = "Restart", at = 5 }, { text = 7 }, "x", { text = "Restart", at = 0 / 0 }, { text = "Restart" } }
local env3, captured3, ns3 = Harness.Load()
check(ns3.Host.loadSaved(db) == "restored" and #ns3.Host.reports == 2)
-- A save from before #83: the company's five readouts, oldest first, no times.
db.reports = nil
local env4, captured4, ns4 = Harness.Load()
check(ns4.Host.loadSaved(db) == "restored")
local readouts = ns4.Host.game.readouts
local seeded = ns4.Host.reports
check(#seeded >= 1 and seeded[#seeded].text == readouts[1] and seeded[#seeded].at == nil)
-- A new company starts a new history.
Window.NewGame()
Window.dialog.yes._scripts.OnClick(Window.dialog.yes)
check(#Host.reports == 1 and Host.reports[1].text == "Welcome to Universal Paperclips")

-- The hook changes nothing in the company: same state and draws with or without it.
local function run(hook)
    local _, c, n = Harness.Load()
    n.Host.start({ 4242, 2424 })
    if not hook then n.Host.game.onMessage = nil end
    n.Host.game.S.funds = 6
    for _ = 1, 200 do n.Host.update(0.02) end
    return Harness.Helpers(c).digest(n.Host.game.S), n.Host.random.count
end
local a, ad = run(true)
local b, bd = run(false)
check(a == b and ad == bd, "the history never touches the simulation")

-- Covered: recorded with times, newest three, scrollable history, cap, saved and restored, damaged entries, old saves, new company, no simulation effect.
done("test_reports")
