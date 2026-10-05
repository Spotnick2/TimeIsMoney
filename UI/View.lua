-- View: what the ledger window shows, as a pure function of the game. No frames,
-- no client APIs: tests run it outside WoW. Reading the game never changes it.
local _, ns = ...

local View = {}
ns.View = View

-- JavaScript equality against 0: == also matches false (a boolean flag), ===
-- matches only the number (creativityOn === 0 is never true: the reference
-- keeps creativityOn a boolean, so its row always shows once the Ledger does).
local function looseZero(v) return v == 0 or v == false end
local function strictZero(v) return v == 0 end

-- Panel visibility, in buttonUpdate's order (main.js), for the panels this window
-- has. Later writes win, as in the reference's single pass over the document.
function View.panels(S)
    local show = {}
    show.wireBuyer = S.wireBuyerFlag == 1
    show.investments = not looseZero(S.investmentEngineFlag)
    show.strategy = not looseZero(S.strategyEngineFlag)
    show.megaClippers = not looseZero(S.megaClipperFlag)
    show.autoClippers = not strictZero(S.autoClipperFlag)
    show.revPerSec = not strictZero(S.revPerSecFlag)
    show.computing = not strictZero(S.compFlag)
    show.creativity = not strictZero(S.creativityOn)
    show.projects = not strictZero(S.projectsFlag)
    local human = not strictZero(S.humanFlag)
    show.business, show.manufacturing, show.trust = human, human, human
    show.quantum = not strictZero(S.qFlag)
    return show
end

-- Labels (plan section 2): the reference concept's Time Is Money name.
View.TERMS = {
    clips = "Handfuls of Copper Bolts", make = "Make Copper Bolts", wire = "Copper Bars",
    funds = "Company Funds", price = "Price per Handful", unsold = "Unsold Bolts",
    marketing = "Sales Campaigns", autoClippers = "Whirring Bronze Gizmos", megaClippers = "Thorium Widgets",
    trust = "Board Trust", processors = "Copper Modulators", memory = "White Punch Cards",
    operations = "Operations", creativity = "Ingenuity", yomi = "Cunning",
}

-- A count for display: whole, with thousands separators. Display only: the
-- simulation keeps every fraction (rounding here never decides anything).
-- NaN first, through JSMath: in WoW's Lua NaN compares equal to everything, so
-- x ~= x never catches it and x == math.huge would.
local isNaN = ns.JSMath.isNaN
function View.count(x)
    if isNaN(x) then return "NaN" end
    if x == math.huge then return "Infinity" end
    if x == -math.huge then return "-Infinity" end
    local whole = math.floor(math.abs(x) + 0.5)
    local negative = x < 0 and whole > 0 -- no "-0" once rounded
    local text
    if whole < 1e15 then
        text = string.format("%.0f", whole):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    else
        text = string.format("%.3e", whole)
    end
    return (negative and "-" or "") .. text
end

-- Company funds: one reference unit is one silver (0.25 shows as 25c). Coin
-- presentation with icons and threshold tooltips is #21; this is its text form.
function View.coins(x)
    if isNaN(x) or x == math.huge or x == -math.huge then return View.count(x) end
    local copper = math.floor(math.abs(x) * 100 + 0.5)
    local negative = x < 0 and copper > 0 -- no "-0c" once rounded
    local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
    copper = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = View.count(gold) .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. "c" end
    return (negative and "-" or "") .. table.concat(parts, " ")
end

-- A project's price tag: the reference text (or the reference's computed one),
-- with its units in Time Is Money terms.
local UNITS = {
    { "creat", View.TERMS.creativity }, { "ops", View.TERMS.operations }, { "Trust", View.TERMS.trust },
    { "yomi", View.TERMS.yomi }, { "Yomi", View.TERMS.yomi }, { "MEM", View.TERMS.memory },
}
local function computedTag(name, S)
    if name == "project40b" then return "($" .. View.count(S.bribe) .. ")" end
    -- project51: toLocaleString at first; after a purchase the reference rebuilds the
    -- tag by plain concatenation, without separators.
    if name == "project51" then
        local cost = S.project51.flag == 1 and ns.JSMath.toString(S.qChipCost) or View.count(S.qChipCost)
        return "(" .. cost .. " ops)"
    end
    if name == "project133" then
        return "(" .. View.count(S.threnodyCost) .. " creat, " .. View.count(2 * (S.threnodyCost / 5)) .. " yomi)"
    end
end
function View.priceTag(name, S)
    local text = ns.ProjectText[name]
    local tag = text.priceTag or computedTag(name, S) or ""
    if name == "project216" then tag = "(" .. View.count(S.standardOps) .. " ops)" end
    tag = tag:gsub("%$([%d,]+)", function(n) return View.coins(tonumber((n:gsub(",", "")))) end)
    for _, unit in ipairs(UNITS) do
        tag = tag:gsub("(%d) " .. unit[1] .. "%f[%A]", "%1 " .. unit[2])
    end
    return tag
end

-- The projects on offer, in the order the reference shows them (activeProjects),
-- each with its title, price tag, purpose and whether it can be bought now.
function View.projects(game)
    local list = {}
    for _, project in ipairs(game.S.activeProjects) do
        local entry = ns.Workshop.projectById[project.id]
        local text = ns.ProjectText[entry.name]
        list[#list + 1] = {
            id = project.id, title = text.title, priceTag = View.priceTag(entry.name, game.S),
            purpose = text.purpose, enabled = not game.disabled[project.id],
        }
    end
    return list
end

-- The Negotiation Simulator's text, as the reference shows it: while a tournament
-- runs, its round, the two strategies and the payoff grid (with the move names the
-- grid drew); afterwards, the results by score, the picked strategy marked.
function View.tournament(game)
    local S = game.S
    local lines = {}
    if S.tourneyInProg == 1 then
        -- Run stays disabled while the rounds play (roundSetup reports roundNum + 1).
        if game.disabled.btnRunTournament then
            lines[1] = "Round " .. View.count(math.min(S.currentRound + 1, S.rounds)) .. " of " .. View.count(S.rounds) .. ": "
                .. S.hStrat.name .. " vs " .. S.vStrat.name
        else
            lines[1] = "Pick a strategy, run the tournament, gain " .. View.TERMS.yomi
        end
        local label = game.gridLabel
        local a = label and S.choiceANames[label] or "Move A"
        local b = label and S.choiceBNames[label] or "Move B"
        local grid = S.payoffGrid
        lines[2] = a .. "/" .. a .. ": " .. grid.valueAA .. "," .. grid.valueAA
            .. "   " .. a .. "/" .. b .. ": " .. grid.valueAB .. "," .. grid.valueBA
        lines[3] = b .. "/" .. a .. ": " .. grid.valueBA .. "," .. grid.valueAB
            .. "   " .. b .. "/" .. b .. ": " .. grid.valueBB .. "," .. grid.valueBB
    elseif S.resultsFlag == 1 then
        lines[1] = "Tournament results"
        local picked = S.allStrats[(tonumber(S.pick) or -1) + 1]
        for i, strat in ipairs(S.results) do
            if i > 8 then break end
            local mark = (picked and strat.name == picked.name) and "> " or ""
            lines[#lines + 1] = mark .. i .. ". " .. strat.name .. ": " .. View.count(strat.currentScore)
        end
    end
    return lines
end
