-- Item tooltips (#84): what each item does, with numbers the simulation actually
-- produces. Each rate below is measured over one logical second and compared with
-- the tooltip's number.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window, View = ns.Host, ns.Window, ns.View

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
local function tipOf(key) return View.itemTip(key, game) end
local function second(fn)
    local before = fn()
    game:advanceTo(game.clock.now + 1000)
    return fn() - before
end

-- Every item has its role, category, use and flavour, translated (not a key).
for _, key in ipairs(View.ITEM_KEYS) do
    local t = tipOf(key)
    assert(t and t.title == View.TERMS[key], key)
    for _, field in ipairs({ "category", "use", "flavor" }) do
        assert(type(t[field]) == "string" and not t[field]:find("^item%."), key .. " " .. field)
    end
    assert(View.itemRole(key) and not View.itemRole(key):find("^item%."), key .. " role")
    assert(#t.lines >= 1, key .. " lines")
end
assert(View.rate(1.25) == "1.25" and View.rate(500) == "500" and View.rate(2.5) == "2.5" and View.rate(1234.5) == "1,234.5")
-- Edges: the sign under 1, rounding up into the next whole, huge values.
assert(View.rate(-0.5) == "-0.5" and View.rate(0.999) == "1" and View.rate(1e15 + 0.5) == View.count(1e15 + 0.5, "round"))
-- Singular forms: a new company's first Gizmo makes "1 handful", not "1 handfuls".
S.clipmakerLevel, S.clipperBoost = 1, 1
local first = tipOf("autoClippers")
assert(first.lines[1] == "Each makes 1 handful per second." and first.lines[2] == "1 working: 1 handful per second.")
-- A price coins round also gives its exact amount, as the button does.
S.clipperCost = 5.1537
first = tipOf("autoClippers")
local exact = false
for _, line in ipairs(first.lines) do if line:find("Exactly 5.1537 silver", 1, true) then exact = true end end
assert(exact, "the exact price")

-- Gizmos: per unit and combined, measured. No other source of bolts runs here.
S.wire, S.clipmakerLevel, S.clipperBoost, S.megaClipperLevel = 1e9, 5, 1.25, 0
local made = second(function() return S.clips end)
local t = tipOf("autoClippers")
assert(t.lines[1]:find("Each makes 1.25 handfuls", 1, true))
assert(t.lines[2]:find("5 working: " .. View.rate(made) .. " handfuls", 1, true) and math.abs(made - 6.25) < 1e-9,
    "the combined rate is what the simulation makes: " .. made)
-- Widgets.
S.clipmakerLevel, S.megaClipperLevel, S.megaClipperBoost = 0, 2, 1.5
made = second(function() return S.clips end)
t = tipOf("megaClippers")
assert(t.lines[1]:find("Each makes 750 handfuls", 1, true) and t.lines[2]:find(View.rate(made), 1, true) and made == 1500)
S.megaClipperLevel = 0

-- Modulators: Operations per second, measured below the Punch Cards' cap.
S.compFlag, S.processors, S.memory, S.standardOps, S.tempOps = 1, 7, 1000, 0, 0
local ops = second(function() return S.standardOps end)
t = tipOf("processors")
assert(t.lines[2]:find("7 installed: " .. View.rate(ops) .. " Operations", 1, true) and math.abs(ops - 70) < 1e-6,
    "Operations per second: " .. ops)
t = tipOf("memory")
assert(t.lines[2]:find("1,000,000 Operations", 1, true))

-- Copper Bars: the shipment the button buys.
S.wireSupply, S.wireCost = 1000, 20
t = tipOf("wire")
assert(t.lines[3]:find("1,000 bars for " .. View.money(20), 1, true), "the price as the button shows it")
-- Power: what View.power reports for the same state.
S.farmLevel, S.batteryLevel, S.storedPower = 3, 2, 1234.4
t = tipOf("farms")
assert(t.lines[2]:find("3 running: " .. View.count(View.power(S).production, "round") .. " MW", 1, true))
t = tipOf("batteries")
assert(t.lines[2]:find("Stored: 1,234 of 20,000 MW", 1, true))
-- Harvesters and converters: the last tick's actual amounts.
game.matterRate, game.wireRate, S.harvesterLevel, S.wireDroneLevel = 2, 3, 4, 5
assert(tipOf("harvesters").lines[1]:find(View.spell(200), 1, true))
assert(tipOf("wireDrones").lines[1]:find(View.spell(300), 1, true))

-- In the window: a role line under the item, and the WoW-style tooltip on hover,
-- the name in its item's quality colour once known.
S.wire, S.clipmakerLevel, S.autoClipperFlag = 100, 2, 1
Window.Refresh()
local role = h.shownText("Automatically makes Copper Bolts.")
assert(role, "the role line shows")
local area
for _, w in ipairs(captured.widgets) do if w.itemKey == "autoClippers" and h.visible(w) then area = w end end
assert(area, "the Gizmos row has an item tooltip")
local colours = {}
env.GameTooltip.SetText = function(self, text, r, g, b) self.lines = { text } colours.title = { r, g, b } end
env.GameTooltip.AddLine = function(self, text, r, g, b) self.lines[#self.lines + 1] = text colours[text] = { r, g, b } end
captured.qualities = { [4375] = 2 }
area.scripts.OnEnter(area)
local lines = env.GameTooltip.lines
assert(lines[1] == "Whirring Bronze Gizmos" and colours.title[1] == 0.12, "the name in its quality colour")
assert(lines[2] == "Automation")
local use, flavor = lines[#lines - 1], lines[#lines]
assert(use:find("^Use:") and colours[use][2] == 1 and colours[use][1] < 0.5, "a green Use: line")
assert(flavor:find('^"') and colours[flavor][1] == 1 and colours[flavor][3] == 0, "yellow flavour text")
-- Live while hovered: the next redraw follows the company.
S.clipmakerLevel = 3
Window.Refresh()
local found = false
for _, line in ipairs(env.GameTooltip.lines) do if line:find("3 working", 1, true) then found = true end end
assert(found, "the tooltip follows the company while hovered")
area.scripts.OnLeave(area)
-- Unknown quality: white.
captured.qualities = {}
area.scripts.OnEnter(area)
assert(colours.title[1] == 1 and colours.title[2] == 1)
area.scripts.OnLeave(area)

print("items: every item's tooltip text, rates measured against the simulation, role lines, quality colour, Use and flavour, live updates passed")
