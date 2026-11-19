-- The ledger window (#20): what it shows, that its controls route through the host,
-- and that drawing it never changes the company.
local env, captured, ns, libGlass = dofile("tests/window_harness.lua").Load()
local View, Host, Window = ns.View, ns.Host, ns.Window

-- Display text: one reference unit is one silver; counts keep their sign.
check(View.coins(0.25) == "25c" and View.coins(1000000) == "10,000g" and View.coins(0) == "0c")
check(View.coins(1.5) == "1s 50c" and View.coins(-0.05) == "-5c")
check(View.count(1234567.4) == "1,234,567" and View.count(-12) == "-12" and View.count(0 / 0) == "NaN")
check(View.count(1e300):find("e%+300"))
-- Price tags in Time Is Money terms, the reference's computed ones included.
local S0 = { bribe = 1000000, qChipCost = 10000, threnodyCost = 50000, standardOps = 1234, project51 = { flag = 0 } }
check(View.priceTag("project1", S0) == "(750 Operations)")
check(View.priceTag("project2", S0) == "(1 Board Trust)")
check(View.priceTag("project40b", S0, View.coins) == "(10,000g)")
check(View.priceTag("project51", S0) == "(10,000 Operations)")
-- After a chip purchase the reference rebuilds project51's tag without separators.
S0.project51 = { flag = 1 }
S0.qChipCost = 15000
check(View.priceTag("project51", S0) == "(15000 Operations)")
-- Rounded to zero shows no sign.
check(View.count(-0.3) == "0" and View.coins(-0.001) == "0c")
check(View.priceTag("project133", S0) == "(50,000 Ingenuity, 20,000 Cunning)")
check(View.priceTag("project216", S0) == "(1,234 Operations)")
-- Panels follow buttonUpdate, including its strict comparisons: creativityOn is a
-- boolean, so creativityOn === 0 never holds and its row shows with the Ledger.
local fresh = ns.Workshop.new({ draw = function() return 0.5 end }, false).S
local panels = View.panels(fresh)
check(panels.business and panels.manufacturing and not panels.computing and panels.creativity)
-- trustDiv sits inside compDiv: hidden with it.
check(not panels.trust)
check(not panels.projects and not panels.autoClippers and not panels.wireBuyer)

-- No company: /tim says how to start one; the window is not built.
env.SlashCmdList.TIMEISMONEY("")
check(captured.messages[#captured.messages]:find("/tim start", 1, true) and Window.frame == nil)

-- /tim start opens the window over the new company.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
check(game and Window.frame and Window.frame:IsShown() and env.TimeIsMoneyWindow == Window.frame)
if libGlass then
    local lib = env.LibStub("LibGlass-1.0")
    check(lib.MEDIA == [[Interface\AddOns\TimeIsMoney\Libs\LibGlass-1.0\Media\]], "embedded path")
else
    check(captured.glass.applied > 0, "drawn with the glass material")
end

local h = dofile("tests/window_harness.lua").Helpers(captured)
local button, shownText, digest = h.button, h.shownText, h.digest

-- The opening: production and sales; no computing, no projects yet.
check(shownText("Handfuls of Copper Bolts") and shownText("Company Funds"))
-- The reference's messages are not shown (the Director's strip, #22, presents them).
check(not shownText("Welcome to Universal Paperclips"))
-- Board Trust lives inside the computing panel (trustDiv in compDiv): not yet.
check(not shownText("Board Trust"))
check(not button("btnAddProc") and not button("btnMakeClipper"))
local make = assert(button("btnMakePaperclip"))
check(h.enabled(make) and make.label._text == "Make Copper Bolts")
-- Text sits on the glass's top layer, above the rim (LibGlass review of #56).
check(make.label._parent == make.glass.top, "button text above the rim")
-- Square buttons are 32x32: sliced masks fail on boxes small in both directions.
local raise = assert(button("btnRaisePrice"))
check(raise._width == 32 and raise._height == 32)
-- Disabled square buttons say so with a symbol, not only colour.
game.S.margin = 0.01
Host.update(0.02)
Window.Refresh()
-- Unavailable is shown by the dimmed control and its tooltip, not by the label (#80).
check(button("btnLowerPrice").label._text == "-" and not h.enabled(button("btnLowerPrice")) and button("btnRaisePrice").label._text == "+")

-- Drawing never changes the company: the state is identical after many refreshes.
local before = digest(game.S) .. digest(game.disabled) .. digest(game.readouts)
local draws = Host.random.count
for _ = 1, 20 do Window.Refresh() end
check(digest(game.S) .. digest(game.disabled) .. digest(game.readouts) == before and Host.random.count == draws,
    "refreshing the window changed the company")

-- A control routes through the host: one click makes one handful.
local clips = game.S.clips
make._scripts.OnClick(make)
check(game.S.clips == clips + 1)

-- A disabled control says so in its label, not only in colour.
game.S.funds = 0
Host.update(0.02)
Window.Refresh()
local buy = assert(button("btnBuyWire"))
check(not h.enabled(buy) and not buy.label._text:find("not yet", 1, true) and buy.label._text:find("Buy", 1, true))

-- Projects appear as the game offers them, with their Time Is Money title and cost.
game.S.funds = 100
game.S.projectsFlag = 1 -- the panel opens later in play (at the computing milestone)
Host.update(0.02) -- buttonUpdate enables the purchase
check(Host.click("btnMakeClipper") and game.S.clipmakerLevel == 1)
Host.update(0.05)
Window.Refresh()
check(button("btnMakeClipper"), "gizmos show once affordable")
local project = assert(button("projectButton1"), "Precision Dies on offer")
check(project.label._text:find("Precision Dies", 1, true) and project.label._text:find("750 Operations", 1, true))

-- A long offer list on a short screen: the window stays within the screen and
-- paging reaches every offer (Codex review of #56).
env.UIParent._height = 500
local saved = game.S.activeProjects
local offers = {}
for i = 1, 19 do
    local entry = ns.Workshop.projects[i]
    offers[i] = game.S[entry.name]
end
game.S.activeProjects = offers
Window.Refresh()
check(Window.frame._height <= 500, "window taller than the screen: " .. tostring(Window.frame._height))
local reached, pages = {}, 0
local function nav(label)
    for _, w in ipairs(captured.widgets) do
        if w._type == "Button" and w._shown and w.label and w.label._text and w.label._text:find(label, 1, true) then return w end
    end
end
repeat
    pages = pages + 1
    for _, w in ipairs(captured.widgets) do
        if w._type == "Button" and w._shown and w.id and w.id:find("^projectButton") then reached[w.id] = true end
    end
    local nextPage = nav("Next")
    local more = nextPage and h.enabled(nextPage)
    if more then nextPage._scripts.OnClick(nextPage) end
until not more or pages > 10
for i = 1, 19 do check(reached[offers[i].id], "unreachable offer " .. offers[i].id) end
check(pages > 1 and pages <= 10)
game.S.activeProjects = saved
env.UIParent._height = 768
Window.Refresh()

-- Hidden: the window stops drawing, the company keeps running.
Window.Toggle()
check(not Window.frame:IsShown())
local now = game.clock.now
local text = make.label._text
Host.update(0.5)
Window.Refresh()
check(game.clock.now > now, "hiding the window must not pause the company")
check(make.label._text == text)
Window.Toggle()
check(Window.frame:IsShown())

-- Slice 2: Cartel Investments, the Negotiation Simulator and the Resonance Calculator.
-- Last in the file: it edits the company's state directly.
local S = game.S
S.investmentEngineFlag, S.strategyEngineFlag, S.qFlag = 1, 1, 1
S.compFlag = 1 -- the Resonance Calculator sits inside the computing panel
S.funds, S.operations, S.standardOps, S.memory = 500, 5000, 5000, 10
Host.update(0.02)
Window.Refresh()
check(shownText("Cartel Investments") and shownText("Negotiation Simulator") and shownText("Resonance Calculator"))
-- Before any tournament: the reference's opening text and a Move A/B grid.
check(shownText("Pick strategy, run tournament, gain Cunning") and shownText("Move A / Move B: 0, 0"))
-- Drawing the engines never changes the company either.
local beforeEngines = digest(game.S) .. digest(game.disabled) .. digest(game.selects)
draws = Host.random.count
for _ = 1, 5 do Window.Refresh() end
check(digest(game.S) .. digest(game.disabled) .. digest(game.selects) == beforeEngines and Host.random.count == draws)
-- Deposit routes through the host.
local deposit = assert(button("btnInvest"))
deposit._scripts.OnClick(deposit)
check(S.funds == 0 and S.bankroll == 500)
-- A select opens its options; choosing one sets it in a single step (no passing
-- through the options in between).
local labelled = h.labelled
local risk = assert(labelled("Low Risk  v"))
risk._scripts.OnClick(risk)
check(labelled("Low Risk  ^") and labelled("Med Risk") and labelled("High Risk"))
local values = {}
local realSet = Host.setValue
Host.setValue = function(id, value) values[#values + 1] = value return realSet(id, value) end
local high = labelled("High Risk")
high._scripts.OnClick(high)
Host.setValue = realSet
check(#values == 1 and values[1] == "hi" and game.selects.investStrat.value == "hi")
check(labelled("High Risk  v") and not labelled("Med Risk"), "the list closes after a choice")
local picker = assert(labelled("Pick a Strat  v"))
picker._scripts.OnClick(picker)
local random = assert(labelled("RANDOM"))
random._scripts.OnClick(random)
check(game.selects.stratPicker.value == "0" and labelled("RANDOM  v"))
-- A tournament: the grid with the move names it drew, then "Round n" and the matchup.
Host.update(0.02)
check(Host.click("btnNewTournament") and S.tourneyInProg == 1 and game.gridLabel)
local lines = View.tournament(game)
local a = S.choiceANames[game.gridLabel]
check(lines[1] == "Pick strategy, run tournament, gain Cunning" and lines[2]:find(a .. " / " .. a, 1, true))
check(Host.click("btnRunTournament"))
lines = View.tournament(game)
check(lines[1] == "Round 1" and lines[2] == S.hStrat.name .. " vs " .. S.vStrat.name)
-- Results replace the grid; the picked strategy (strats[pick]) is marked. Played
-- out by the simulation, not edited in.
Host.update(60)
check(S.tourneyInProg == 0 and game.resultsTableDisplay == "", "the tournament finished")
lines = View.tournament(game)
check(lines[1]:find("^TOURNAMENT RESULTS %(roll over for ") and lines[2]:find("^> 1%. RANDOM: "))
-- Hovering the tournament area is the reference's mouseover: the grid comes back
-- and resultsTimer resets, holding automatic tournaments until the pointer leaves
-- (Codex review of #57). The hover area keeps its size across the swap.
Window.Refresh()
local area
for _, w in ipairs(captured.widgets) do
    if w._type == "Frame" and w._scripts.OnEnter and w._shown and not w.newTagArea and not w.chips and not w.cardTitle then area = w end
end
check(area, "the tournament hover area")
local resultsHeight = area._height
S.autoTourneyFlag, S.autoTourneyStatus, S.resultsTimer = 1, 1, 299
S.operations, S.standardOps = 50000, 50000
area._scripts.OnEnter(area)
check(S.resultsTimer == 0 and game.resultsTableDisplay == "none")
check(View.tournament(game)[2]:find(" / ", 1, true), "the grid shows while hovered")
check(area._height == resultsHeight, "the hover area keeps its size")
local level = S.tourneyLvl
Host.update(4) -- 400 buttonUpdates: no automatic tournament while the grid is held
check(S.tourneyLvl == level and S.resultsTimer == 0)
area._scripts.OnLeave(area)
check(game.resultsTableDisplay == "" and View.tournament(game)[2]:find("^> 1%. RANDOM: "))
S.autoTourneyStatus = 0
-- The window fits the screen in both directions, whatever is open: every engine,
-- five stocks, both selects open, on a 1024x500 screen.
for i = 1, 5 do
    S.stocks[i] = { id = i, symbol = "S" .. i, amount = 1000000, price = 15, total = 15000000, profit = -123456, age = 0 }
end
S.portfolioSize = 5
env.UIParent._height = 500
for _, text in ipairs({ "High Risk  v", "RANDOM  v" }) do
    local b = assert(labelled(text))
    b._scripts.OnClick(b)
end
Window.Refresh()
local scale = Window.frame._scale or 1
check(Window.frame._width * scale <= 1024 and Window.frame._height * scale <= 500,
    "window does not fit: " .. Window.frame._width .. "x" .. Window.frame._height .. " at " .. scale)
for _, text in ipairs({ "High Risk  ^", "RANDOM  ^" }) do
    local b = assert(labelled(text))
    b._scripts.OnClick(b)
end
env.UIParent._height = 768
Window.Refresh()
check((Window.frame._scale or 1) <= 1)
-- The Resonance Calculator: no crystals yet, then a computed result that fades.
check(Host.click("btnQcompute") and View.qComp(game) == "Need Arcane Crystals")
S.qChips[1].active, S.qChips[1].value = 1, 0.5
check(Host.click("btnQcompute") and View.qComp(game) == "qOps: 180")
Window.Refresh()
local result = assert(shownText("qOps: 180"))
check(result._alpha == nil or result._alpha > 0.9)
S.qFade = 0.2
Window.Refresh()
check(math.abs(result._alpha - 0.2) < 1e-9, "the result fades with qFade")
-- Stocks: two lines each; after a sale the slot just past the last stock keeps what
-- it showed (the reference's off-by-one clear), later slots are blank.
local slots = {}
local stocks = {}
for i = 1, 5 do stocks[i] = { symbol = "S" .. i, amount = 10.2, price = 1.5, total = 15, profit = -0.4 } end
local fake = { stocks = stocks }
check(#View.stockLines(fake, slots, View.coins) == 10)
check(View.stockLines(fake, slots, View.coins)[1] == "S1  x11 @ 2s"
    and View.stockLines(fake, slots, View.coins)[2]:find("P/L 0c", 1, true))
stocks[5], stocks[4] = nil, nil
lines = View.stockLines(fake, slots, View.coins)
check(#lines == 8 and lines[7] == "S4  x11 @ 2s", "slot 4 keeps the sold stock; slot 5 cleared")

-- Covered: display text, price tags, panel rules, routing, no state change from drawing, disabled labels, projects and hidden refresh.
done(libGlass and "test_window (real LibGlass)" or "test_window (LibGlass stand-in)")
