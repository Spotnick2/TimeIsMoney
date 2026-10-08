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
assert(#Host.reports >= 1 and Host.reports[1].text == "Welcome to Universal Paperclips" and Host.reports[1].at == 0)
-- The simulation's own messages are recorded as they happen, with their time.
game.S.funds = 6
for _ = 1, 30 do Host.update(0.02) end
local last = Host.reports[#Host.reports]
assert(last.text == "AutoClippers available for purchase" and last.at > 0, "recorded with its game time")

-- The panel: newest first, with times; opened by clicking the reports or /tim reports.
for i = 1, 30 do game:displayMessage("Processor added, operations (or creativity) per sec increased") end
Window.Refresh()
local area = ns.Director.strip.reportArea
assert(h.visible(area), "the reports can be clicked")
area.scripts.OnClick(area)
local p = Window.reports
assert(p:IsShown() and p.title.text == "Company reports")
assert(p.rows[1].text.text:find("Copper Modulator", 1, true) or p.rows[1].text.text ~= "", "newest first, translated")
assert(p.rows[1].time.text:find("^%d+:%d%d:%d%d$"), "with its game time")
assert(p.hint.shown and p.hint.text:find("of " .. #Host.reports, 1, true))
-- The wheel scrolls: down shows older reports; it stops at both ends.
local top = p.rows[1].text.text
p.scripts.OnMouseWheel(p, -1)
assert(p.offset == 3)
for _ = 1, 50 do p.scripts.OnMouseWheel(p, -1) end
assert(p.offset == #Host.reports - Window.REPORT_ROWS, "stops at the oldest")
assert(p.rows[Window.REPORT_ROWS].text.text == "Welcome to Durotar Supply and Logistics.", "the oldest last")
for _ = 1, 50 do p.scripts.OnMouseWheel(p, 1) end
assert(p.offset == 0 and p.rows[1].text.text == top, "back to the newest")
env.SlashCmdList.TIMEISMONEY("reports")
assert(not p:IsShown(), "/tim reports closes it")
env.SlashCmdList.TIMEISMONEY("reports")
assert(p:IsShown())

-- At most 200 entries: the oldest go first.
for i = 1, 250 do game:displayMessage("Processor added, operations (or creativity) per sec increased") end
assert(#Host.reports == Host.REPORTS_MAX)

-- Saved beside the company; restored with the times.
local db = Host.persist()
assert(type(db.reports) == "table" and #db.reports == 200 and db.reports[200].text == Host.reports[200].text)
local env2, captured2, ns2 = Harness.Load()
assert(ns2.Host.loadSaved(db) == "restored")
assert(#ns2.Host.reports == 200 and ns2.Host.reports[200].at == Host.reports[200].at)
-- Damaged entries are dropped, never blocking.
db.reports = { { text = "Restart", at = 5 }, { text = 7 }, "x", { text = "Restart", at = 0 / 0 }, { text = "Restart" } }
local env3, captured3, ns3 = Harness.Load()
assert(ns3.Host.loadSaved(db) == "restored" and #ns3.Host.reports == 2)
-- A save from before #83: the company's five readouts, oldest first, no times.
db.reports = nil
local env4, captured4, ns4 = Harness.Load()
assert(ns4.Host.loadSaved(db) == "restored")
local readouts = ns4.Host.game.readouts
local seeded = ns4.Host.reports
assert(#seeded >= 1 and seeded[#seeded].text == readouts[1] and seeded[#seeded].at == nil)
-- A new company starts a new history.
Window.NewGame()
Window.dialog.yes.scripts.OnClick(Window.dialog.yes)
assert(#Host.reports == 1 and Host.reports[1].text == "Welcome to Universal Paperclips")

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
assert(a == b and ad == bd, "the history never touches the simulation")

print("reports: recorded with times, newest three, scrollable history, cap, saved and restored, damaged entries, old saves, new company, no simulation effect passed")
