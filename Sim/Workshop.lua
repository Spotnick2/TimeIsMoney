-- Phase-one workshop slice of the pinned reference (main.js/globals.js): manual
-- production, wire purchases, price/demand/sales, revenue tracking, marketing,
-- AutoClippers/MegaClippers, trust and milestones, plus the always-running battle
-- core. Source identifiers, formulas and statement order are preserved; state
-- uses the reference global names. Reference paths outside this slice stop with
-- an explicit unported error naming the issue that will port them.
local _, ns = ...
ns = ns or {}

local JSMath, Scheduler, Battle = ns.JSMath, ns.Scheduler, ns.Battle
local floor, ceil = math.floor, math.ceil
local round, pow, num, undefined = JSMath.round, JSMath.pow, JSMath.num, JSMath.undefined

function ns.Unported(what, issue)
    error("Unported reference path: " .. what .. " (issue " .. issue .. ")", 0)
end
local Unported = ns.Unported

-- JavaScript truthiness for reference conditions such as `if (creativityOn)`.
local function truthy(v)
    return v ~= nil and v ~= false and v ~= 0 and v == v and v ~= "" and v ~= undefined
end

local Workshop = {}

-- Initial values of the ported globals (globals.js, main.js, combat.js).
Workshop.initial = {
    clips = 0, unusedClips = 0, clipRate = 0, clipRateTemp = 0, prevClips = 0, clipRateTracker = 0,
    clipmakerLevel = 0, clipperCost = 5, unsoldClips = 0, funds = 0, margin = .25, wire = 1000,
    wireCost = 20, adCost = 100, demand = 5, clipsSold = 0, avgRev = 0, income = 0, ticks = 0,
    marketing = 1, marketingLvl = 1, trust = 2, nextTrust = 3000, transaction = 1, clipperBoost = 1,
    wirePurchase = 0, wireSupply = 1000, marketingEffectiveness = 1, milestoneFlag = 0,
    fib1 = 2, fib2 = 3, compFlag = 0, projectsFlag = 0, autoClipperFlag = 0, megaClipperFlag = 0,
    megaClipperCost = 500, megaClipperLevel = 0, megaClipperBoost = 1, wireBuyerFlag = 0,
    demandBoost = 1, humanFlag = 1, wirePriceCounter = 0, wireBasePrice = 20, wirePriceTimer = 0,
    wireBuyerStatus = 1, qFade = 1, prestigeU = 0, dismantle = 0, finalClips = 0,
    factoryLevel = 0, factoryBoost = 1, factoryRate = 1000000000, powMod = 0,
    incomeThen = undefined, incomeNow = undefined, trueAvgRev = undefined, avgSales = undefined,
    incomeLastSecond = undefined, sum = undefined,
    secTimer = 0, saveTimer = 0, sellDelay = 0, stockReportCounter = 0,
    riskiness = 5, maxPort = 5, m = 0, secTotal = 0, portTotal = 0, portfolioSize = 0, bankroll = 0,
    probeUsedTrust = 0, probeNav = 0, probeRep = 0, probeHaz = 0, probeFac = 0, probeHarv = 0,
    probeWire = 0,
    -- Read by guards and conditions only in this slice.
    creativityOn = false, operations = 0, memory = 1, qFlag = 0, spaceFlag = 0,
    investmentEngineFlag = 0, swarmFlag = 0, resultsFlag = 0, autoTourneyFlag = 0,
    autoTourneyStatus = 1, endTimer6 = 0, blinkCounter = 0,
}
for key, value in pairs(Battle.initial) do Workshop.initial[key] = value end

-- Array-valued globals (encoded as arrays even when empty).
Workshop.arrays = { incomeTracker = true, ships = true, battles = true, stocks = true, activeProjects = true }

-- Project availability (manageProjects) for every project whose trigger reads only
-- state this slice changes, in projects.js registration order. The other triggers
-- read project flags (purchases are #8) or later-phase values that keep their
-- initial, non-triggering values here.
Workshop.projects = {
    { "project1", "projectButton1", function(S) return S.clipmakerLevel >= 1 end },
    { "project2", "projectButton2", function(S)
        return S.portTotal < S.wireCost and S.funds < S.wireCost and S.wire < 1 and S.unsoldClips < 1
    end },
    { "project3", "projectButton3", function(S) return S.operations >= (S.memory * 1000) end },
    { "project6", "projectButton6", function(S) return truthy(S.creativityOn) end },
    { "project7", "projectButton7", function(S) return S.wirePurchase >= 1 end },
    { "project8", "projectButton8", function(S) return S.wireSupply >= 1500 end },
    { "project9", "projectButton9", function(S) return S.wireSupply >= 2600 end },
    { "project10", "projectButton10", function(S) return S.wireSupply >= 5000 end },
    { "project10b", "projectButton10b", function(S) return S.wireCost >= 125 end },
    { "project21", "projectButton21", function(S) return S.trust >= 8 end },
    { "project22", "projectButton22", function(S) return S.clipmakerLevel >= 75 end },
    { "project26", "projectButton26", function(S) return S.wirePurchase >= 15 end },
    { "project37", "projectButton37", function(S) return S.portTotal >= 10000 end },
    { "project42", "projectButton42", function(S) return S.projectsFlag == 1 end },
    { "project40", "projectButton40", function(S)
        return S.humanFlag == 1 and S.trust >= 85 and S.trust < 100 and S.clips >= 101000000
    end },
    { "project121", "projectButton121", function(S) return S.probesLostCombat >= 10000000 end },
    { "project131", "projectButton131", function(S) return S.probesLostCombat >= 1 end },
    { "project217", "projectButton217", function(S) return S.operations <= -10000 end },
}

-- Buttons whose disabled state buttonUpdate maintains; clicks on a disabled
-- control do nothing, as in the browser.
Workshop.buttons = {
    "btnMakePaperclip", "btnBuyWire", "btnMakeClipper", "btnExpandMarketing",
    "btnLowerPrice", "btnRaisePrice", "btnMakeMegaClipper",
}

local Game = {}
Game.__index = Game

local function copy(value)
    if type(value) ~= "table" or value == undefined then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

-- random: an object with draw(site, at) returning the next simulation value.
-- log: the ordered trace event list shared with the random stream.
function Workshop.new(random, log)
    local game = setmetatable({}, Game)
    game.clock = Scheduler.new(log)
    local S = copy(Workshop.initial)
    S.incomeTracker = { 0 }
    S.battles, S.stocks, S.activeProjects = {}, {}, {}
    for _, project in ipairs(Workshop.projects) do
        S[project[1]] = { id = project[2], flag = 0, uses = 1 }
    end
    game.S = S
    game.disabled = {}
    for _, id in ipairs(Workshop.buttons) do game.disabled[id] = false end
    game.readouts = { "Welcome to Universal Paperclips", "", "", "", "" }
    game.investStrat = "low"
    game.draw = function(site) return random:draw(site, game.clock.now) end

    -- combat.js load: new Battle() restarts, initialize() starts the 16 ms
    -- Update interval and restarts again.
    Battle.restart(S, game.draw)
    game.clock:register(function() Battle.update(S, game.draw) end, 16, true)
    Battle.restart(S, game.draw)
    -- main.js intervals in source registration order.
    game.clock:register(function() game:portfolioInterval() end, 100, true)
    game.clock:register(function() game:stockShopInterval() end, 1000, true)
    game.clock:register(function() game:stockSellInterval() end, 2500, true)
    -- `pick = stratPickerElement.value`: strategy selection belongs to #7.
    game.clock:register(function() end, 100, true)
    game.clock:register(function() game:mainLoop() end, 10, true)
    game.clock:register(function() game:slowLoop() end, 100, true)
    return game
end

function Game:displayMessage(msg)
    local r = self.readouts
    r[5], r[4], r[3], r[2], r[1] = r[4], r[3], r[2], r[1], msg
end

-- timeCruncher: JavaScript % is fmod.
local function timeCruncher(t)
    local x = t / 100
    local h = floor(x / 3600)
    local m = floor(JSMath.mod(x, 3600) / 60)
    local s = floor(JSMath.mod(JSMath.mod(x, 3600), 60))
    local hDisplay = h > 0 and (h .. (h == 1 and " hour " or " hours ")) or ""
    local mDisplay = m > 0 and (m .. (m == 1 and " minute " or " minutes ")) or ""
    local sDisplay = s > 0 and (s .. (s == 1 and " second" or " seconds")) or ""
    return hDisplay .. mDisplay .. sDisplay
end
Workshop.timeCruncher = timeCruncher

-- Projects ---------------------------------------------------------------

-- blink(element): a 30 ms interval sharing the global blinkCounter; the element's
-- visibility toggling is presentation.
function Game:blink()
    local S, clock = self.S, self.clock
    local handle
    handle = clock:register(function()
        S.blinkCounter = S.blinkCounter + 1
        if S.blinkCounter >= 12 then
            clock:clear(handle)
            S.blinkCounter = 0
        end
    end, 30, true)
end

-- manageProjects: newly triggered projects become active and blink. The
-- per-project button eligibility (cost) is presentation in this slice.
function Game:manageProjects()
    local S = self.S
    for _, entry in ipairs(Workshop.projects) do
        local project = S[entry[1]]
        if entry[3](S) and project.uses > 0 then
            self:blink()
            project.uses = project.uses - 1
            S.activeProjects[#S.activeProjects + 1] = project
        end
    end
end

-- Wire ---------------------------------------------------------------------

function Game:adjustWirePrice()
    local S = self.S
    S.wirePriceTimer = S.wirePriceTimer + 1
    if S.wirePriceTimer > 250 and S.wireBasePrice > 15 then
        S.wireBasePrice = S.wireBasePrice - (S.wireBasePrice / 1000)
        S.wirePriceTimer = 0
    end
    if self.draw("main.js:704:14") < .015 then
        S.wirePriceCounter = S.wirePriceCounter + 1
        local wireAdjust = 6 * (math.sin(S.wirePriceCounter))
        S.wireCost = ceil(S.wireBasePrice + wireAdjust)
    end
end

function Game:buyWire()
    local S = self.S
    if S.funds >= S.wireCost then
        S.wirePriceTimer = 0
        S.wire = S.wire + S.wireSupply
        S.funds = S.funds - S.wireCost
        S.wirePurchase = S.wirePurchase + 1
        S.wireBasePrice = S.wireBasePrice + .05
    end
end

-- Production -------------------------------------------------------------

function Game:clipClick(number)
    local S = self.S
    if S.dismantle >= 4 then Unported("clipClick during dismantling", "#17") end
    if S.wire >= 1 then
        if number > S.wire then number = S.wire end
        S.clips = S.clips + number
        S.unsoldClips = S.unsoldClips + number
        S.wire = S.wire - number
        S.unusedClips = S.unusedClips + number
    end
end

function Game:makeClipper()
    local S = self.S
    if S.funds >= S.clipperCost then
        S.clipmakerLevel = S.clipmakerLevel + 1
        S.funds = S.funds - S.clipperCost
    end
    S.clipperCost = (pow(1.1, S.clipmakerLevel) + 5)
end

function Game:makeMegaClipper()
    local S = self.S
    if S.funds >= S.megaClipperCost then
        S.megaClipperLevel = S.megaClipperLevel + 1
        S.funds = S.funds - S.megaClipperCost
    end
    S.megaClipperCost = (pow(1.07, S.megaClipperLevel) * 1000)
end

-- Business ---------------------------------------------------------------

function Game:buyAds()
    local S = self.S
    if S.funds >= S.adCost then
        S.marketingLvl = S.marketingLvl + 1
        S.funds = S.funds - S.adCost
        S.adCost = floor(S.adCost * 2)
    end
end

function Game:sellClips(clipsDemanded)
    local S = self.S
    if S.unsoldClips > 0 then
        if clipsDemanded > S.unsoldClips then
            S.transaction = (floor((S.unsoldClips * S.margin) * 1000)) / 1000
            S.funds = S.funds + S.transaction
            S.income = S.income + S.transaction
            S.clipsSold = S.clipsSold + S.unsoldClips
            S.unsoldClips = 0
        else
            S.transaction = (floor((clipsDemanded * S.margin) * 1000)) / 1000
            S.funds = (floor((S.funds + S.transaction) * 100)) / 100
            S.income = S.income + S.transaction
            S.clipsSold = S.clipsSold + clipsDemanded
            S.unsoldClips = S.unsoldClips - clipsDemanded
        end
    end
end

function Game:raisePrice()
    local S = self.S
    S.margin = (round((S.margin + .01) * 100)) / 100
end

function Game:lowerPrice()
    local S = self.S
    if S.margin >= .01 then
        S.margin = (round((S.margin - .01) * 100)) / 100
    end
end

function Game:calculateRev()
    local S = self.S
    S.incomeThen = S.incomeNow
    S.incomeNow = S.income
    S.incomeLastSecond = round((num(S.incomeNow) - num(S.incomeThen)) * 100) / 100
    local tracker = S.incomeTracker
    tracker[#tracker + 1] = S.incomeLastSecond
    if #tracker > 10 then table.remove(tracker, 1) end
    S.sum = 0
    for i = 1, #tracker do
        S.sum = round((S.sum + tracker[i]) * 100) / 100
    end
    S.trueAvgRev = S.sum / #tracker
    local chanceOfPurchase = S.demand / 100
    if chanceOfPurchase > 1 then chanceOfPurchase = 1 end
    if S.unsoldClips < 1 then chanceOfPurchase = 0 end
    S.avgSales = chanceOfPurchase * (.7 * pow(S.demand, 1.15)) * 10
    S.avgRev = chanceOfPurchase * (.7 * pow(S.demand, 1.15)) * S.margin * 10
    if S.demand > S.unsoldClips then
        S.avgRev = S.trueAvgRev
        S.avgSales = S.avgRev / S.margin
    end
end

-- Trust and milestones ---------------------------------------------------

function Game:calculateTrust()
    local S = self.S
    if S.clips > (S.nextTrust - 1) then
        S.trust = S.trust + 1
        self:displayMessage("Production target met: TRUST INCREASED, additional processor/memory capacity granted")
        local fibNext = S.fib1 + S.fib2
        S.nextTrust = fibNext * 1000
        S.fib1 = S.fib2
        S.fib2 = fibNext
    end
end

local clipMilestones = {
    [1] = { 500, "500 clips created in " },
    [2] = { 1000, "1,000 clips created in " },
    [3] = { 10000, "10,000 clips created in " },
    [4] = { 100000, "100,000 clips created in " },
    [5] = { 1000000, "1,000,000 clips created in " },
}

function Game:milestoneCheck()
    local S = self.S
    if S.milestoneFlag == 0 and S.funds >= 5 then
        S.milestoneFlag = S.milestoneFlag + 1
        self:displayMessage("AutoClippers available for purchase")
    end
    for flag = 1, 2 do
        local m = clipMilestones[flag]
        if S.milestoneFlag == flag and ceil(S.clips) >= m[1] then
            S.milestoneFlag = S.milestoneFlag + 1
            self:displayMessage(m[2] .. timeCruncher(S.ticks))
        end
    end
    if S.compFlag == 0 and S.unsoldClips < 1 and S.funds < S.wireCost and S.wire < 1 then
        S.compFlag = 1
        S.projectsFlag = 1
        self:displayMessage("Trust-Constrained Self-Modification enabled")
    end
    if S.compFlag == 0 and ceil(S.clips) >= 2000 then
        S.compFlag = 1
        S.projectsFlag = 1
        self:displayMessage("Trust-Constrained Self-Modification enabled")
    end
    for flag = 3, 5 do
        local m = clipMilestones[flag]
        if S.milestoneFlag == flag and ceil(S.clips) >= m[1] then
            S.milestoneFlag = S.milestoneFlag + 1
            self:displayMessage(m[2] .. timeCruncher(S.ticks))
        end
    end
    -- Milestone 6 needs project35 (#8); later milestones cannot be reached first.
end

-- buttonUpdate: the state it changes and the slice's control eligibility.
function Game:buttonUpdate()
    local S, disabled = self.S, self.disabled
    S.qFade = S.qFade - .001
    if S.resultsFlag == 1 and S.autoTourneyFlag == 1 then Unported("automatic tournaments", "#7") end
    if S.humanFlag == 0 then Unported("phase-two controls", "#11") end
    disabled.btnMakePaperclip = S.wire < 1
    disabled.btnBuyWire = S.funds < S.wireCost
    disabled.btnMakeClipper = S.funds < S.clipperCost
    disabled.btnExpandMarketing = S.funds < S.adCost
    disabled.btnLowerPrice = S.margin <= .01
    disabled.btnMakeMegaClipper = S.funds < S.megaClipperCost
    if S.funds >= 5 then S.autoClipperFlag = 1 end
    S.probeUsedTrust = (S.probeSpeed + S.probeNav + S.probeRep + S.probeHaz + S.probeFac + S.probeHarv + S.probeWire + S.probeCombat)
end

-- Intervals --------------------------------------------------------------

-- main.js:1617, every 100 ms: investment risk and portfolio totals.
function Game:portfolioInterval()
    local S = self.S
    if self.investStrat == "low" then
        S.riskiness = 7
    elseif self.investStrat == "med" then
        S.riskiness = 5
    else
        S.riskiness = 1
    end
    S.m = 0
    if S.portfolioSize > 0 then Unported("portfolio valuation", "#7") end
    S.secTotal = S.m
    S.portTotal = S.bankroll + S.secTotal
    S.portfolioSize = #S.stocks
end

-- main.js:1666, every second: stockShop.
function Game:stockShopInterval()
    local S = self.S
    if S.humanFlag ~= 1 then return end
    local budget = ceil(S.portTotal / S.riskiness)
    local r = 11 - S.riskiness
    local reserves = ceil(S.portTotal / r)
    if S.riskiness == 1 then reserves = 0 end
    if (S.bankroll - budget) < reserves and S.riskiness == 1 and S.bankroll > (S.portTotal / 10) then
        budget = S.bankroll
    elseif (S.bankroll - budget) < reserves and S.riskiness == 1 then
        budget = 0
    elseif (S.bankroll - budget) < reserves then
        budget = S.bankroll - reserves
    end
    if S.portfolioSize < S.maxPort and S.bankroll >= 5 and budget >= 1 and S.bankroll - budget >= reserves then
        Unported("stock purchases", "#7")
    end
end

-- main.js:1673, every 2.5 seconds: stock sales and updates.
function Game:stockSellInterval()
    local S = self.S
    S.sellDelay = S.sellDelay + 1
    if S.portfolioSize > 0 then Unported("stock sales and updates", "#7") end
end

-- main.js:4188, every 10 ms.
function Game:mainLoop()
    local S = self.S
    S.ticks = S.ticks + 1
    self:milestoneCheck()
    self:buttonUpdate()
    if S.compFlag == 1 then Unported("calculateOperations", "#6") end
    if S.humanFlag == 1 then self:calculateTrust() end
    if S.qFlag == 1 then Unported("quantumCompute", "#6") end
    -- updateStats only writes presentation.
    self:manageProjects()
    self:milestoneCheck()

    S.clipRateTracker = S.clipRateTracker + 1
    if S.clipRateTracker < 100 then
        local cr = S.clips - S.prevClips
        S.clipRateTemp = S.clipRateTemp + cr
        S.prevClips = S.clips
    else
        S.clipRateTracker = 0
        S.clipRate = S.clipRateTemp
        S.clipRateTemp = 0
    end

    if S.investmentEngineFlag == 1 then Unported("investment report", "#7") end
    if S.humanFlag == 1 and S.wireBuyerFlag == 1 and S.wireBuyerStatus == 1 and S.wire <= 1 then
        self:buyWire()
    end
    if S.probeCount >= 1 then Unported("exploreUniverse", "#14") end
    if S.humanFlag == 0 then Unported("planetary production", "#11") end

    local fbst = 1
    if S.factoryBoost > 1 then fbst = S.factoryBoost * S.factoryLevel end
    if S.dismantle < 4 then
        self:clipClick(S.powMod * fbst * (floor(S.factoryLevel) * S.factoryRate))
    end
    if S.spaceFlag == 1 then Unported("probe functions", "#14") end

    if S.dismantle < 4 then
        self:clipClick(S.clipperBoost * (S.clipmakerLevel / 100))
        self:clipClick(S.megaClipperBoost * (S.megaClipperLevel * 5))
    end

    if S.humanFlag == 1 then
        S.marketing = (pow(1.1, (S.marketingLvl - 1)))
        S.demand = (((.8 / S.margin) * S.marketing * S.marketingEffectiveness) * S.demandBoost)
        S.demand = S.demand + ((S.demand / 10) * S.prestigeU)
    end

    if truthy(S.creativityOn) and S.operations >= (S.memory * 1000) then
        Unported("calculateCreativity", "#6")
    end
    if S.dismantle >= 1 then Unported("ending sequence", "#17") end
    -- End timers advance only after ending projects (#17); endTimer6 stays 0.
end

-- main.js:4564, every 100 ms: wire price, sales, revenue and auto-save.
function Game:slowLoop()
    local S = self.S
    self:adjustWirePrice()
    if S.humanFlag == 1 then
        if self.draw("main.js:4574:18") < (S.demand / 100) then
            self:sellClips(floor(.7 * pow(S.demand, 1.15)))
        end
        S.secTimer = S.secTimer + 1
        if S.secTimer >= 10 then
            self:calculateRev()
            S.secTimer = 0
        end
    end
    S.saveTimer = S.saveTimer + 1
    if S.saveTimer >= 250 then Unported("reference auto-save", "#19") end
end

-- Commands ---------------------------------------------------------------

local clicks = {
    btnMakePaperclip = function(game) game:clipClick(1) end,
    btnBuyWire = Game.buyWire,
    btnMakeClipper = Game.makeClipper,
    btnExpandMarketing = Game.buyAds,
    btnLowerPrice = Game.lowerPrice,
    btnRaisePrice = Game.raisePrice,
    btnMakeMegaClipper = Game.makeMegaClipper,
}

-- A click on a disabled control has no effect, matching the browser host.
function Game:click(id)
    local handler = clicks[id]
    if not handler then Unported("control " .. tostring(id), "a later slice") end
    if self.disabled[id] then return end
    handler(self)
end

function Game:advanceTo(target, after, maxCallbacks)
    self.clock:advanceTo(target, after, maxCallbacks)
end

Workshop.Game = Game
ns.Workshop = Workshop
return Workshop
