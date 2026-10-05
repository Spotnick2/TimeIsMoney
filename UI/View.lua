-- View: what the ledger window shows, as a pure function of the game. No frames,
-- no client APIs: tests run it outside WoW. Reading the game never changes it.
local _, ns = ...

local View = {}
ns.View = View

-- JavaScript equality against 0: == also matches false (a boolean flag), ===
-- matches only the number (creativityOn === 0 is never true: the reference
-- keeps creativityOn a boolean, so its row always shows once the Ledger does).
local function looseZero(v) return v == 0 or v == false end
-- JavaScript's < (false for NaN; WoW's Lua compares NaN true).
local function lt(a, b) return ns.JSMath.lt(a, b) end
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
    -- Phase II (buttonUpdate, then the space branch that hides the planetary panels).
    local space = not strictZero(S.spaceFlag)
    show.creation = not human
    show.factoryUpgrade = not (S.maxFactoryLevel >= 50 or S.project45.flag == 0)
    show.droneUpgrade = S.maxDroneLevel < 50000
    show.toth = not strictZero(S.tothFlag)
    show.factory = not strictZero(S.factoryFlag) and not space
    show.wireProduction = not strictZero(S.wireProductionFlag)
    show.wireTrans = not show.wireProduction -- hidden once wire production starts
    show.harvester = not strictZero(S.harvesterFlag) and not space
    show.wireDrone = not strictZero(S.wireDroneFlag) and not space
    show.power = S.project127.flag == 1 and S.spaceFlag == 0
    show.mdps = S.spaceFlag == 1
    show.swarm = not looseZero(S.swarmFlag)
    show.swarmSlider = S.swarmFlag == 1
    -- In space, probes build: factoryDivSpace and droneDivSpace replace the rows.
    show.factorySpace = space
    show.droneSpace = space
    -- Phase III.
    show.space = space
    show.probeDesign = space
    show.increaseProbeTrust = space
    show.increaseMaxTrust = S.project121.flag ~= 0
    show.honor = S.project121.flag ~= 0
    show.drifters = not looseZero(S.battleFlag)
    show.battle = not looseZero(S.battleFlag)
    show.combatAllocation = S.project131.flag ~= 0
    show.lostHazards = not lt(S.probesLostHaz, 1)
    show.lostDrift = not lt(S.probesLostDrift, 1)
    show.lostCombat = not lt(S.probesLostCombat, 1)
    show.prestige = not (S.prestigeU < 1 and S.prestigeS < 1)
    show.swarmGift = show.swarm
    show.clipsPerSec, show.processor, show.qCompute = true, true, true
    -- The ending (main.js "// Ending", which runs after buttonUpdate in the same main
    -- loop tick, so its hiding wins): each dismantling and its end timer close panels
    -- in order until only manual production remains.
    -- The reference checks endTimer1/2/4 before the same tick increments them; the
    -- view reads the state after the tick, so it takes the value the check saw.
    local d, t1, t2, t4 = S.dismantle, View.checkedTimer(S, 1), View.checkedTimer(S, 2), View.checkedTimer(S, 4)
    if d >= 1 then
        show.probeDesign = false
        if t1 >= 50 then show.increaseProbeTrust = false end
        if t1 >= 100 then show.increaseMaxTrust = false end
        if t1 >= 150 then show.space = false end
        if t1 >= 175 then show.battle = false end
        if t1 >= 190 then show.honor = false end
    end
    if d >= 2 then
        show.wireProduction, show.wireTrans = false, true
        if t2 >= 50 then show.swarmGift = false end
        if t2 >= 100 then show.swarm = false end
        if t2 >= 150 then show.swarmSlider = false end
    end
    if d >= 3 then show.factorySpace, show.clipsPerSec, show.toth = false, false, false end
    if d >= 4 then show.strategy = false end
    if d >= 5 then
        show.qCompute = false
        if t4 >= 250 then show.quantum = false end
    end
    if d >= 6 then show.processor = false end
    if d >= 7 then show.computing, show.projects = false, false end
    if S.endTimer6 >= 250 then show.creation = false end -- incremented before its check
    -- compDiv holds trustDiv, swarmGiftDiv, processorDisplay, swarmEngine,
    -- swarmSliderDiv and qComputing: hidden with it.
    if not show.computing then
        show.trust, show.swarmGift, show.processor = false, false, false
        show.swarm, show.swarmSlider, show.quantum = false, false, false
    end
    return show
end

-- Labels (plan section 2): the reference concept's Time Is Money name.
View.TERMS = {
    clips = "Handfuls of Copper Bolts", make = "Make Copper Bolts", wire = "Copper Bars",
    funds = "Company Funds", price = "Price per Handful", unsold = "Unsold Bolts",
    marketing = "Sales Campaigns", autoClippers = "Whirring Bronze Gizmos", megaClippers = "Thorium Widgets",
    trust = "Board Trust", processors = "Copper Modulators", memory = "White Punch Cards",
    operations = "Operations", creativity = "Ingenuity", yomi = "Cunning", chips = "Arcane Crystals",
    unused = "Available Bolts", availableMatter = "Unclaimed Material", acquiredMatter = "Reclaimed Material",
    harvesters = "Compact Harvest Reapers", wireDrones = "Delicate Arcanite Converters", factories = "Bolt Foundries",
    farms = "Gold Power Cores", batteries = "9-60 Battery Packs", swarm = "Company Network",
    swarmGifts = "Network Breakthroughs",
    colonized = "Cosmos Surveyed", drift = "Charter Drift", drifters = "Breakaway Franchises",
    probeTrust = "Dragonling Trust", honor = "Renown", probeSpeed = "Rift Engines", probeNav = "Cosmic Surveying",
    probeRep = "Franchise Replication", probeHaz = "Protective Wards", probeFac = "Foundry Deployment",
    probeHarv = "Salvage Deployment", probeWire = "Refinery Deployment", probeCombat = "Enforcement",
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

-- Company funds (spec section 4): one reference unit is one silver, so 0.25 shows
-- as 25c, 1 as 1s, 123.45 as 1g 23s 45c and 1,000,000 as 10,000g. Display only:
-- the simulation keeps the exact number, and nothing here decides affordability.
-- Rounded to the nearest copper; once copper counts pass 2^53 (where whole copper
-- is no longer exact) only the gold shows. The sign survives; a value that rounds
-- to nothing shows no sign.
local COIN_TEXT = { g = "g", s = "s", c = "c" }
local EXACT_COPPER = 2 ^ 53
-- The coin icons Forever's money frames use (AltStable shows them on Forever too),
-- sized to the line, with the letters as their readable equivalent in tooltips.
View.COIN_ICONS = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local function coinParts(x, marks)
    if isNaN(x) or x == math.huge or x == -math.huge then return View.count(x) end
    local copper = math.floor(math.abs(x) * 100 + 0.5)
    local negative = x < 0 and copper > 0
    local parts = {}
    if copper >= EXACT_COPPER then
        parts[1] = View.count(math.floor(math.abs(x) / 100)) .. marks.g
    else
        local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
        copper = copper % 100
        if gold > 0 then parts[#parts + 1] = View.count(gold) .. marks.g end
        if silver > 0 then parts[#parts + 1] = silver .. marks.s end
        if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. marks.c end
    end
    return (negative and "-" or "") .. table.concat(parts, " ")
end
function View.coins(x) return coinParts(x, COIN_TEXT) end
-- The same amount with coin icons, for the window.
function View.money(x) return coinParts(x, View.COIN_ICONS) end

-- The exact amount, when the coins round it (a fraction of a copper): the tooltip
-- that keeps thresholds visible. nil when the coins already show it exactly. The
-- number's own shortest text decides (0.29 is whole copper even though 0.29 * 100
-- is not exactly 29 in doubles): more than two decimals, or an exponent, rounds.
function View.exactMoney(x)
    if isNaN(x) or x == math.huge or x == -math.huge then return nil end
    if math.abs(x) * 100 >= EXACT_COPPER then return nil end
    local text = ns.JSMath.toString(x)
    local decimals = text:match("%.(%d+)$")
    if not text:find("e", 1, true) and (not decimals or #decimals <= 2) then return nil end
    return "Exactly " .. text .. " silver (" .. View.coins(x) .. " shown)"
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
function View.priceTag(name, S, money)
    money = money or View.money
    local text = ns.ProjectText[name]
    local tag = text.priceTag or computedTag(name, S) or ""
    if name == "project216" then tag = "(" .. View.count(S.standardOps) .. " ops)" end
    tag = tag:gsub("%$([%d,]+)", function(n) return money(tonumber((n:gsub(",", "")))) end)
    for _, unit in ipairs(UNITS) do
        tag = tag:gsub("(%d) " .. unit[1] .. "%f[%A]", "%1 " .. unit[2])
    end
    return tag
end

-- The projects on offer, in the order the reference shows them (activeProjects),
-- each with its title, price tag, purpose and whether it can be bought now.
function View.projects(game, money)
    local list = {}
    for _, project in ipairs(game.S.activeProjects) do
        local entry = ns.Workshop.projectById[project.id]
        local text = ns.ProjectText[entry.name]
        list[#list + 1] = {
            id = project.id, name = entry.name, title = text.title, priceTag = View.priceTag(entry.name, game.S, money),
            purpose = text.purpose, enabled = not game.disabled[project.id],
        }
    end
    return list
end

-- The picked strategy as the reference reads it: strats[pick] (the pool, in
-- purchase order), only when pick < 10; nil otherwise.
function View.picked(S)
    local pick = tonumber(S.pick)
    if not pick or pick >= 10 or pick < 0 or pick ~= math.floor(pick) then return nil end
    return S.strats[pick + 1]
end

-- The Negotiation Simulator, as the reference shows it:
-- - tourneyDisplay: its initial text, "Round n" while rounds play, then the results
--   heading (kept on the game as presentation by the simulation);
-- - the two strategies of the current round (vertStrat/horizStrat);
-- - the payoff grid with the move names it drew, unless the results replaced it;
--   hovering the area (revealGrid, a host command) shows the grid again.
function View.tournament(game)
    local S, T = game.S, View.TERMS
    local lines = {}
    local report = game.tourneyReport
    if not report or report.kind == "pick" then
        lines[1] = "Pick strategy, run tournament, gain " .. T.yomi
    elseif report.kind == "round" then
        lines[1] = "Round " .. report.round
    else
        lines[1] = "TOURNAMENT RESULTS (roll over for " .. report.grid .. ")"
    end
    if game.matchup then lines[#lines + 1] = game.matchup.h .. " vs " .. game.matchup.v end
    -- The grid table shows unless displayTourneyReport swapped in the results (both
    -- tables start shown, the results one empty).
    if S.resultsFlag == 1 and game.resultsTableDisplay == "" then
        local picked = View.picked(S)
        for i, strat in ipairs(S.results) do
            if i > 8 then break end
            local mark = (picked and strat.name == picked.name) and "> " or ""
            lines[#lines + 1] = mark .. i .. ". " .. strat.name .. ": " .. View.count(strat.currentScore)
        end
    else
        local label = game.gridLabel
        local a = label and S.choiceANames[label] or "Move A"
        local b = label and S.choiceBNames[label] or "Move B"
        local grid = S.payoffGrid
        -- One cell per line (row move / column move: row payoff, column payoff).
        lines[#lines + 1] = a .. " / " .. a .. ": " .. grid.valueAA .. ", " .. grid.valueAA
        lines[#lines + 1] = a .. " / " .. b .. ": " .. grid.valueAB .. ", " .. grid.valueBA
        lines[#lines + 1] = b .. " / " .. a .. ": " .. grid.valueBA .. ", " .. grid.valueAB
        lines[#lines + 1] = b .. " / " .. b .. ": " .. grid.valueBB .. ", " .. grid.valueBB
    end
    return lines
end

-- The Resonance Calculator's result: nil before any compute, else the reference's
-- text with the plan's name for the chips.
-- Lines the tournament area keeps, whichever of grid or results it shows, so the
-- area (and its hover target) does not change size when they swap.
function View.tournamentLines(game)
    local S = game.S
    return 1 + (game.matchup and 1 or 0) + math.max(4, math.min(8, #S.results))
end

function View.qComp(game)
    local result = game.qCompResult
    if result == nil then return nil end
    if result == false then return "Need " .. View.TERMS.chips end
    return "qOps: " .. View.count(result)
end

-- The stock table: two lines per stock, the reference's whole numbers (Math.ceil),
-- in five slots. The reference clears the slots after the last stock starting one
-- too late (main.js "Frank Fix"), so the slot just after the last stock keeps what
-- it last showed; slots carries that between redraws (window state, not saved).
function View.stockLines(S, slots, money)
    money = money or View.money
    local n = math.min(5, #S.stocks)
    for i = 1, 5 do
        local stock = S.stocks[i]
        if i <= n then
            slots[i] = {
                stock.symbol .. "  x" .. View.count(math.ceil(stock.amount)) .. " @ " .. money(math.ceil(stock.price)),
                "    = " .. money(math.ceil(stock.total)) .. "   P/L " .. money(math.ceil(stock.profit)),
            }
        elseif i > n + 1 then
            slots[i] = nil
        end
    end
    local lines = {}
    for i = 1, 5 do
        if slots[i] then
            lines[#lines + 1] = slots[i][1]
            lines[#lines + 1] = slots[i][2]
        end
    end
    return lines
end

-- spellf (main.js), as written: the whole part's digits (JavaScript's toString,
-- with "e+" expanded), then its leading group with the next two digits after a
-- point, through formatWithCommas(num, 1), and the place name. 12345678 shows as
-- "12.3 million ". Its quirks stay: below 1,000 ".0" is added and any fraction
-- dropped, and a tiny "Ne-k" value is read as text ("1e-7" gives "NaN.0 thousand ").
local PLACES = {
    "", " thousand ", " million ", " billion ", " trillion ", " quadrillion ", " quintillion ", " sextillion ",
    " septillion ", " octillion ", " nonillion ", " decillion ", " undecillion ", " duodecillion ",
    " tredecillion ", " quattuordecillion ", " quindecillion ", " sexdecillion ", " septendecillion ",
    " octodecillion ", " novemdecillion  ", " vigintillion ", " unvigintillion ", " duovigintillion ",
    " trevigintillion ", " quattuorvigintillion ", " quinvigintillion ", " sexvigintillion ",
    " septenvigintillion ", " octovigintillion ", " novemvigintillion ", " trigintillion ", " untrigintillion ",
    " duotrigintillion ", " tretrigintillion ", " quattuortrigintillion ", " quintrigintillion ",
    " sextrigintillion ", " septentrigintillion ", " octotrigintillion ", " novemtrigintillion ",
    " quadragintillion ", " unquadragintillion ", " duoquadragintillion ", " trequadragintillion ",
    " quattuorquadragintillion ", " quinquadragintillion ", " sexquadragintillion ", " septenquadragintillion ",
    " octoquadragintillion ", " novemquadragintillion ", " quinquagintillion ", " unquinquagintillion ",
    " duoquinquagintillion ", " trequinquagintillion ", " quattuorquinquagintillion ", " quinquinquagintillion ",
    " sexquinquagintillion ", " septenquinquagintillion ", " octoquinquagintillion ", " novemquinquagintillion ",
    " sexagintillion ", " unsexagintillion ", " duosexagintillion ", " tresexagintillion ",
    " quattuorsexagintillion ", " quinsexagintillion ", " sexsexagintillion ", " septsexagintillion ",
    " octosexagintillion ", " octosexagintillion ", " septuagintillion ", " unseptuagintillion ",
    " duoseptuagintillion ", " treseptuagintillion ", " quinseptuagintillion", " sexseptuagintillion",
    " septseptuagintillion", " octoseptuagintillion", " novemseptuagintillion", " octogintillion",
    " unoctogintillion", " duooctogintillion", " treoctogintillion", " quattuoroctogintillion",
    " quinoctogintillion", " sexoctogintillion", " septoctogintillion", " octooctogintillion",
    " novemoctogintillion", " nonagintillion", " unnonagintillion", " duononagintillion", " trenonagintillion ",
    " quattuornonagintillion ", " quinnonagintillion ", " sexnonagintillion ", " septnonagintillion ",
    " octononagintillion ", " novemnonagintillion ", " centillion"
}
function View.spell(x)
    local JSMath = ns.JSMath
    if JSMath.lt(x, 0) then return JSMath.toString(x) end
    local text = JSMath.toString(x)
    local mantissa, exponent = text:match("^(.-)e%+(%d+)$")
    if mantissa then
        local whole, fraction = mantissa:match("^(%d+)%.(%d+)$")
        exponent = tonumber(exponent)
        if whole then
            exponent = exponent - #fraction
            mantissa = whole .. fraction
        end
        text = mantissa .. string.rep("0", exponent)
    elseif text:find(".", 1, true) then
        text = text:match("^(.-)%.")
    end
    -- The reference throws "Number out of bonds!" here; the window shows the count.
    if #text >= 303 then return View.count(x) end
    local asNumber = JSMath.toNumber(text)
    if not isNaN(asNumber) and asNumber == 0 then return "0" end
    local groups = math.ceil(#text / 3)
    local lead = #text - 3 * (groups - 1)
    local num = JSMath.toNumber(text:sub(1, lead) .. "." .. text:sub(lead + 1, lead + 2))
    return ns.Workshop.formatWithCommas(num, 1) .. (PLACES[groups] or "")
end

-- An end timer as the reference's ending block checked it this tick: endTimer1, 2
-- and 4 are incremented after the checks when their project is bought (148, 211,
-- 213), so the state after the tick is one ahead of what was checked.
local TIMER_PROJECT = { [1] = "project148", [2] = "project211", [4] = "project213" }
function View.checkedTimer(S, n)
    local value = S["endTimer" .. n]
    if S[TIMER_PROJECT[n]].flag == 1 then value = value - 1 end
    return value
end

-- The photonic chips the ending has not yet taken: from the fifth dismantling, chip
-- 10 goes at the first time in Workshop.chipTimes, ... chip 1 at the last.
function View.chipShown(S, i)
    local times = ns.Workshop.chipTimes
    return not (S.dismantle >= 5 and View.checkedTimer(S, 4) >= times[#times + 1 - i])
end

-- updateUpgrades: the next factory and drone counts that unlock an upgrade.
function View.nextUpgrades(S)
    local nfup, ndup = 0, 0
    if S.maxFactoryLevel < 10 then nfup = 10 elseif S.maxFactoryLevel < 20 then nfup = 20
    elseif S.maxFactoryLevel < 50 then nfup = 50 end
    if S.maxDroneLevel < 500 then ndup = 500 elseif S.maxDroneLevel < 5000 then ndup = 5000
    elseif S.maxDroneLevel < 50000 then ndup = 50000 end
    return nfup, ndup
end

-- updatePower's printed figures (MW-seconds per tick times 100, as the reference
-- prints them), recomputed from the state it uses.
function View.power(S)
    local supply = S.farmLevel * S.farmRate / 100
    local dDemand = (S.harvesterLevel * S.dronePowerRate / 100) + (S.wireDroneLevel * S.dronePowerRate / 100)
    local fDemand = S.factoryLevel * S.factoryPowerRate / 100
    local performance = 0
    if not (S.factoryLevel == 0 and S.harvesterLevel == 0 and S.wireDroneLevel == 0) then
        performance = math.floor(S.powMod * 100 + 0.5)
    end
    return {
        production = supply * 100, consumption = (dDemand + fDemand) * 100, factories = fDemand * 100,
        drones = dDemand * 100, stored = S.storedPower, capacity = S.batteryLevel * S.batterySize,
        performance = performance,
    }
end

-- The Company Network's status text (swarmStatus); 7 hides the status line.
local SWARM = { [0] = "Active", [1] = "Hungry", [2] = "Confused", [3] = "Bored", [4] = "Cold",
    [5] = "Disorganized", [6] = "Sleeping", [8] = "Lonely", [9] = "NO RESPONSE..." }
function View.swarmStatus(S)
    return SWARM[S.swarmStatus]
end

-- Number.prototype.toFixed for the display: with no decimals it rounds an exact tie
-- up (JavaScript picks the larger n), which %.0f would round to even.
-- Exact comparison for toFixed: the sign of a * 10^digits * 2 - k2, with a a finite
-- nonnegative double and k2 a nonnegative integer below 2^53, in integers base 1e7.
local function big(n)
    local out = {}
    repeat
        out[#out + 1] = n % 1e7
        n = math.floor(n / 1e7)
    until n == 0
    return out
end
local function mul(x, factor) -- factor up to 2^20
    local carry = 0
    for i = 1, #x do
        local v = x[i] * factor + carry
        x[i] = v % 1e7
        carry = math.floor(v / 1e7)
    end
    while carry > 0 do
        x[#x + 1] = carry % 1e7
        carry = math.floor(carry / 1e7)
    end
end
local function mulPow2(x, k)
    while k > 0 do
        local step = math.min(k, 20)
        mul(x, 2 ^ step)
        k = k - step
    end
end
local function compare(x, y)
    while #x > 1 and x[#x] == 0 do x[#x] = nil end
    while #y > 1 and y[#y] == 0 do y[#y] = nil end
    if #x ~= #y then return #x < #y and -1 or 1 end
    for i = #x, 1, -1 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end
local function exactCompare(a, digits, k2)
    if a == 0 then return k2 == 0 and 0 or -1 end
    local m, e = math.frexp(a)
    local left, right = big(m * 2 ^ 53), big(k2)
    e = e - 53
    for _ = 1, digits do mul(left, 10) end
    mul(left, 2)
    if e >= 0 then mulPow2(left, e) else mulPow2(right, -e) end
    return compare(left, right)
end

-- A negative value keeps its sign even when it rounds to zero ("-0"), and from
-- 1e21 up JavaScript gives the number's own text.
function View.toFixed(x, digits)
    local JSMath = ns.JSMath
    if isNaN(x) then return "NaN" end
    if math.abs(x) >= 1e21 then return JSMath.toString(x) end
    local sign = JSMath.lt(x, 0) and "-" or ""
    local a = math.abs(x)
    -- n / 10^digits nearest the exact value of x, a tie going to the larger n (the
    -- C runtime's %f rounds ties to even, and its digits are not exact). Decided by
    -- exact comparisons of x's binary value against the candidates.
    if a * 10 ^ digits >= 2 ^ 51 then return sign .. string.format("%." .. digits .. "f", a) end
    local n = math.floor(a * 10 ^ digits)
    while exactCompare(a, digits, 2 * n) < 0 do n = n - 1 end
    while exactCompare(a, digits, 2 * (n + 1)) >= 0 do n = n + 1 end
    if exactCompare(a, digits, 2 * n + 1) >= 0 then n = n + 1 end -- a tie or above: up
    local text = string.format("%.0f", n)
    if digits == 0 then return sign .. text end
    text = string.rep("0", digits + 1 - #text) .. text
    return sign .. text:sub(1, #text - digits) .. "." .. text:sub(#text - digits + 1)
end

-- numberCruncher (main.js): a count divided down to its place name, toFixed.
local CRUNCH = { { 51, "sexdecillion" }, { 48, "quindecillion" }, { 45, "quattuordecillion" },
    { 42, "tredecillion" }, { 39, "duodecillion" }, { 36, "undecillion" }, { 33, "decillion" },
    { 30, "nonillion" }, { 27, "octillion" }, { 24, "septillion" }, { 21, "sextillion" },
    { 18, "quintillion" }, { 15, "quadrillion" }, { 12, "trillion" }, { 9, "billion" }, { 6, "million" },
    { 3, "thousand" } }
for _, step in ipairs(CRUNCH) do
    -- The reference's literals: 999...9 (k nines) and 1000...0, parsed as doubles
    -- exactly as JavaScript parses them.
    step.above = tonumber(string.rep("9", step[1]))
    step.divisor = tonumber("1" .. string.rep("0", step[1]))
end
function View.numberCruncher(number, decimals)
    local precision = decimals or 2
    local suffix = ""
    for _, step in ipairs(CRUNCH) do
        if ns.JSMath.gt(number, step.above) then
            number, suffix = number / step.divisor, step[2]
            break
        end
    end
    if suffix == "" and ns.JSMath.lt(number, 1000) then precision = 0 end
    return View.toFixed(number, precision) .. " " .. suffix
end

-- The share of the universe explored, as the reference prints it.
function View.colonized(S)
    return View.toFixed(ns.JSMath.div(100, ns.JSMath.div(S.totalMatter, S.foundMatter)), 12)
end

-- checkForBattleEnd's result panel: shown while a battle has ended on one side, once
-- Renown exists. Its DEFEAT branch runs first and always writes the left side's
-- ships; the VICTORY branch then overwrites the text and sign, writing the reward
-- only on the battle's first award. So when both fleets fall together it reads
-- VICTORY with the left side's count. Numbers are written raw (no separators).
function View.battleResult(S)
    if #S.battles == 0 or S.project121.flag ~= 1 then return nil end
    local JSMath = ns.JSMath
    if S.numRightShips == 0 then
        local amount = S.numLeftShips == 0 and S.battleLEFTSHIPS or S.honorReward
        return "VICTORY", "+" .. JSMath.toString(amount)
    end
    if S.numLeftShips == 0 then return "DEFEAT", "-" .. JSMath.toString(S.battleLEFTSHIPS) end
    return nil
end
