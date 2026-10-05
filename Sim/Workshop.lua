-- Phase-one workshop slice of the pinned reference (main.js/globals.js). The game
-- loop calls into Sim/Investments.lua and Sim/Strategy.lua, which Sim/Reference.lua
-- always loads after this file. Manual
-- production, wire purchases, price/demand/sales, revenue tracking, marketing,
-- AutoClippers/MegaClippers, trust and milestones, processors/memory, Operations,
-- creativity and quantum computing, plus the always-running battle core. Source identifiers, formulas and statement order are preserved; state
-- uses the reference global names. Reference paths outside this slice stop with
-- an explicit unported error naming the issue that will port them.
local _, ns = ...
ns = ns or {}

local JSMath, Scheduler, Battle = ns.JSMath, ns.Scheduler, ns.Battle
local floor, ceil = math.floor, math.ceil
local round, pow, num, undefined = JSMath.round, JSMath.pow, JSMath.num, JSMath.undefined
local sin, log10, div, lt, gt = JSMath.sin, JSMath.log10, JSMath.div, JSMath.lt, JSMath.gt

function ns.Unported(what, issue)
    error("Unported reference path: " .. what .. " (issue " .. issue .. ")", 0)
end
local Unported = ns.Unported

-- JavaScript truthiness for reference conditions such as `if (creativityOn)`.
local function truthy(v)
    return v ~= nil and v ~= false and v ~= 0 and v == v and v ~= "" and v ~= undefined
end

local Workshop = {}
Workshop.truthy = truthy
-- Per-game initializers registered by later simulation files (setup(game, S)).
Workshop.setups = {}
-- Control states later simulation files add to buttonUpdate (fn(game, S, disabled)),
-- run in registration order before probeUsedTrust, and the late ones after it.
Workshop.buttonUpdates = {}
Workshop.lateButtonUpdates = {}

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
    endTimer1 = 0, endTimer2 = 0, endTimer3 = 0, endTimer4 = 0, endTimer5 = 0,
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
    -- Computation (#6).
    processors = 1, standardOps = 0, tempOps = 0, opFade = 0, opFadeTimer = 0, opFadeDelay = 800,
    creativity = 0, creativityCounter = 0, creativitySpeed = 1, prestigeS = 0, qClock = 0,
    swarmGifts = 0,
}
for key, value in pairs(Battle.initial) do Workshop.initial[key] = value end

-- Array-valued globals (encoded as arrays even when empty).
Workshop.arrays = {
    incomeTracker = true, ships = true, battles = true, stocks = true, activeProjects = true, qChips = true,
    battleNumbers = true,
}

-- Projects in projects.js registration order: {name, id, trigger, cost, effect},
-- defined by Sim/Projects.lua.
Workshop.projects = {}
Workshop.projectById = {}

-- Controls the slice ports, with their disabled state in every checkpoint. A click
-- on a disabled control does nothing, as in the browser. buttonUpdate maintains
-- most of them; btnRaisePrice, btnQcompute, btnInvest, btnWithdraw and
-- btnToggleAutoTourney are never disabled, and newTourney/runTourney set
-- btnRunTournament.
Workshop.buttons = {
    "btnMakePaperclip", "btnBuyWire", "btnMakeClipper", "btnExpandMarketing",
    "btnLowerPrice", "btnRaisePrice", "btnMakeMegaClipper", "btnAddProc", "btnAddMem", "btnQcompute",
    "btnToggleWireBuyer",
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
    -- qChip0..qChip9 (main.js): wave seeds .1 to 1, activated by photonic chip purchases.
    S.qChips = {}
    for i, seed in ipairs({ .1, .2, .3, .4, .5, .6, .7, .8, .9, 1 }) do
        S.qChips[i] = { waveSeed = seed, value = 0, active = 0 }
    end
    for _, project in ipairs(Workshop.projects) do
        S[project.name] = { id = project.id, flag = 0, uses = 1 }
    end
    game.S = S
    game.disabled = {}
    game.projectElements = {} -- project buttons currently in the document
    for _, id in ipairs(Workshop.buttons) do game.disabled[id] = false end
    game.readouts = { "Welcome to Universal Paperclips", "", "", "", "" }
    -- Select controls the slice reads: options in document order and the value.
    game.selects = {
        investStrat = { options = { "low", "med", "hi" }, value = "low" },
        stratPicker = { options = { "10", "0" }, value = "10" },
    }
    -- Range inputs (value plus a sanitize function), added by later files.
    game.ranges = {}
    for _, setup in ipairs(Workshop.setups) do setup(game, S) end
    game.draw = function(site) return random:draw(site, game.clock.now) end

    -- combat.js load: new Battle() restarts, initialize() starts the 16 ms
    -- Update interval and restarts again.
    Battle.restart(S, game.draw)
    game:schedule("battle", 16, true)
    Battle.restart(S, game.draw)
    -- main.js intervals in source registration order.
    game:schedule("portfolio", 100, true)
    game:schedule("stockShop", 1000, true)
    game:schedule("stockSell", 2500, true)
    game:schedule("pick", 100, true)
    game:schedule("main", 10, true)
    game:schedule("slow", 100, true)
    return game
end

-- Timer callbacks by kind, so a saved game rebuilds its pending timers (#19). Each
-- receives the game and the timer's own id (blink intervals clear themselves).
Workshop.timers = {
    battle = function(game) Battle.update(game.S, game.draw) end,
    portfolio = function(game) game:portfolioInterval() end,
    stockShop = function(game) game:stockShopInterval() end,
    stockSell = function(game) game:stockSellInterval() end,
    pick = function(game) game.S.pick = game.selects.stratPicker.value end,
    main = function(game) game:mainLoop() end,
    slow = function(game) game:slowLoop() end,
}

function Game:timerCallback(kind, id)
    local fn = Workshop.timers[kind]
    if not fn then error("Unknown timer kind " .. tostring(kind), 2) end
    local game = self
    return function() fn(game, id) end
end

function Game:schedule(kind, delay, repeating)
    local clock = self.clock
    local id = clock.nextId
    local registered = clock:register(self:timerCallback(kind, id), delay, repeating, kind)
    if registered ~= id then error("Timer ids out of order", 2) end
    return id
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
    self:schedule("blink", 30, true)
end
function Workshop.timers.blink(game, handle)
    local S = game.S
    S.blinkCounter = S.blinkCounter + 1
    if S.blinkCounter >= 12 then
        game.clock:clear(handle)
        S.blinkCounter = 0
    end
end

-- manageProjects: newly triggered projects get a button (displayProjects, which
-- blinks it) and become active; then every active button is enabled exactly when
-- its cost is met.
function Game:manageProjects()
    local S = self.S
    for _, entry in ipairs(Workshop.projects) do
        local project = S[entry.name]
        if entry.trigger(S) and project.uses > 0 then
            self.projectElements[entry.id] = true
            self.disabled[entry.id] = false
            self:blink()
            project.uses = project.uses - 1
            S.activeProjects[#S.activeProjects + 1] = project
        end
    end
    for _, project in ipairs(S.activeProjects) do
        self.disabled[project.id] = not Workshop.projectById[project.id].cost(S)
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
        local wireAdjust = 6 * (JSMath.sin(S.wirePriceCounter))
        S.wireCost = ceil(S.wireBasePrice + wireAdjust)
    end
end

-- The WireBuyer switch (the status text is presentation).
function Game:toggleWireBuyer()
    local S = self.S
    if S.wireBuyerStatus == 1 then
        S.wireBuyerStatus = 0
    else
        S.wireBuyerStatus = 1
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
    -- From the strategy engine's dismantling on, every click is a final clip (#17).
    if S.dismantle >= 4 then S.finalClips = S.finalClips + 1 end
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
    -- NaN for the first second (incomeThen starts undefined), so no native division.
    S.incomeLastSecond = div(round((num(S.incomeNow) - num(S.incomeThen)) * 100), 100)
    local tracker = S.incomeTracker
    tracker[#tracker + 1] = S.incomeLastSecond
    if #tracker > 10 then table.remove(tracker, 1) end
    S.sum = 0
    for i = 1, #tracker do
        S.sum = div(round((S.sum + tracker[i]) * 100), 100)
    end
    S.i = #tracker -- the loop uses the global i
    S.trueAvgRev = div(S.sum, #tracker)
    -- demand is NaN at a zero price; comparisons follow JavaScript (NaN is false).
    local chanceOfPurchase = div(S.demand, 100)
    if gt(chanceOfPurchase, 1) then chanceOfPurchase = 1 end
    if S.unsoldClips < 1 then chanceOfPurchase = 0 end
    S.avgSales = chanceOfPurchase * (.7 * pow(S.demand, 1.15)) * 10
    S.avgRev = chanceOfPurchase * (.7 * pow(S.demand, 1.15)) * S.margin * 10
    if gt(S.demand, S.unsoldClips) then
        S.avgRev = S.trueAvgRev
        S.avgSales = div(S.avgRev, S.margin)
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

-- Thresholds are the doubles nearest 10^12 ... 10^27 (the reference literals),
-- built with the correctly rounded pow rather than C decimal parsing.
local lateMilestones = {
    [7] = { pow(10, 12), "One Trillion Clips Created in " },
    [8] = { pow(10, 15), "One Quadrillion Clips Created in " },
    [9] = { pow(10, 18), "One Quintillion Clips Created in " },
    [10] = { pow(10, 21), "One Sextillion Clips Created in " },
    [11] = { pow(10, 24), "One Septillion Clips Created in " },
    [12] = { pow(10, 27), "One Octillion Clips Created in " },
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
    if S.milestoneFlag == 6 and S.project35.flag == 1 then
        S.milestoneFlag = S.milestoneFlag + 1
        self:displayMessage("Full autonomy attained in " .. timeCruncher(S.ticks))
    end
    for flag = 7, 12 do
        local m = lateMilestones[flag]
        if S.milestoneFlag == flag and ceil(S.clips) >= m[1] then
            S.milestoneFlag = S.milestoneFlag + 1
            self:displayMessage(m[2] .. timeCruncher(S.ticks))
        end
    end
    if S.milestoneFlag == 13 and S.spaceFlag == 1 then
        S.milestoneFlag = S.milestoneFlag + 1
        self:displayMessage("Terrestrial resources fully utilized in " .. timeCruncher(S.ticks))
    end
    -- Milestone 15: all the universe's matter in clips, or surveyed and used up. It
    -- opens the Emperor of Drift's correspondence (#16).
    if S.milestoneFlag == 14 and S.clips >= S.totalMatter then
        S.milestoneFlag = S.milestoneFlag + 1
        self:displayMessage("Universal Paperclips achieved in " .. timeCruncher(S.ticks))
    end
    if S.milestoneFlag == 14 and S.foundMatter >= S.totalMatter and S.availableMatter < 1 and S.wire < 1 then
        S.milestoneFlag = S.milestoneFlag + 1
        self:displayMessage("Universal Paperclips achieved in " .. timeCruncher(S.ticks))
    end
end

-- buttonUpdate: the state it changes and the slice's control eligibility.
function Game:buttonUpdate()
    local S, disabled = self.S, self.disabled
    S.qFade = S.qFade - .001
    self:autoTourney()
    disabled.btnMakePaperclip = S.wire < 1
    disabled.btnBuyWire = S.funds < S.wireCost
    disabled.btnMakeClipper = S.funds < S.clipperCost
    disabled.btnExpandMarketing = S.funds < S.adCost
    disabled.btnLowerPrice = S.margin <= .01
    disabled.btnAddProc = S.trust <= S.processors + S.memory and JSMath.le(S.swarmGifts, 0)
    disabled.btnAddMem = disabled.btnAddProc
    disabled.btnNewTournament = not (S.operations >= S.tourneyCost and S.tourneyInProg == 0)
    disabled.btnImproveInvestments = S.yomi < S.investUpgradeCost
    disabled.btnMakeMegaClipper = S.funds < S.megaClipperCost
    if S.funds >= 5 then S.autoClipperFlag = 1 end
    if S.humanFlag == 0 then
        S.investmentEngineFlag = 0
        S.wireBuyerFlag = 0
    end
    for _, update in ipairs(Workshop.buttonUpdates) do update(self, S, disabled) end
    S.probeUsedTrust = (S.probeSpeed + S.probeNav + S.probeRep + S.probeHaz + S.probeFac + S.probeHarv + S.probeWire + S.probeCombat)
    for _, update in ipairs(Workshop.lateButtonUpdates) do update(self, S, disabled) end
end

-- Computation ------------------------------------------------------------

-- JavaScript `value == 1`: true also equals 1.
local function looseOne(v) return v == 1 or v == true end

-- Math.pow(processors, 1.1) matches V8 for every count up to this bound
-- (tests/reference/jsmath.test.cjs); the first known difference is at 3,425.
Workshop.VERIFIED_PROCESSORS = 3424

function Game:addProc()
    local S = self.S
    if S.trust > 0 or gt(S.swarmGifts, 0) then
        -- Stop before changing state, so a caught error leaves the game intact.
        if S.processors + 1 > Workshop.VERIFIED_PROCESSORS then
            Unported("creativitySpeed beyond the verified processor count", "#24")
        end
        S.processors = S.processors + 1
        S.creativitySpeed = log10(S.processors) * pow(S.processors, 1.1) + S.processors - 1
        if looseOne(S.creativityOn) then
            self:displayMessage("Processor added, operations (or creativity) per sec increased")
        else
            self:displayMessage("Processor added, operations per sec increased")
        end
        if S.humanFlag == 0 then S.swarmGifts = S.swarmGifts - 1 end
    end
end

function Game:addMem()
    local S = self.S
    if S.trust > 0 or gt(S.swarmGifts, 0) then
        self:displayMessage("Memory added, max operations increased")
        S.memory = S.memory + 1
        if S.humanFlag == 0 then S.swarmGifts = S.swarmGifts - 1 end
    end
end

function Game:calculateOperations()
    local S = self.S
    if S.tempOps > 0 then S.opFadeTimer = S.opFadeTimer + 1 end
    if S.opFadeTimer > S.opFadeDelay and S.tempOps > 0 then
        S.opFade = S.opFade + pow(3, 3.5) / 1000
    end
    if S.tempOps > 0 then
        S.tempOps = round(S.tempOps - S.opFade)
    else
        S.tempOps = 0
    end
    if S.tempOps + S.standardOps < S.memory * 1000 then
        S.standardOps = S.standardOps + S.tempOps
        S.tempOps = 0
    end
    S.operations = floor(S.standardOps + floor(S.tempOps))
    if S.operations < S.memory * 1000 then
        local opCycle = S.processors / 10
        local opBuf = (S.memory * 1000) - S.operations
        if opCycle > opBuf then opCycle = opBuf end
        S.standardOps = S.standardOps + opCycle
    end
    if S.standardOps > S.memory * 1000 then S.standardOps = S.memory * 1000 end
end

function Game:calculateCreativity()
    local S = self.S
    S.creativityCounter = S.creativityCounter + 1
    local creativityThreshold = 400
    local s = S.prestigeS / 10
    local ss = S.creativitySpeed + (S.creativitySpeed * s)
    local creativityCheck = div(creativityThreshold, ss)
    if S.creativityCounter >= creativityCheck then
        if creativityCheck >= 1 then S.creativity = S.creativity + 1 end
        if creativityCheck < 1 then S.creativity = (S.creativity + ss / creativityThreshold) end
        S.creativityCounter = 0
    end
end

-- Chip opacity is presentation; each value is Math.sin of the shared clock.
function Game:quantumCompute()
    local S = self.S
    S.qClock = S.qClock + .01
    for _, chip in ipairs(S.qChips) do
        chip.value = sin(S.qClock * chip.waveSeed * chip.active)
    end
end

-- qComp: a negative chip sum subtracts Operations; overflow above memory becomes
-- fading temporary Operations.
function Game:qComp()
    local S = self.S
    S.qFade = 1
    local q = 0
    -- qCompDisplay's text is presentation: kept on the game for the window, not in
    -- the state (never saved; a reloaded company shows it empty until the next run).
    if S.qChips[1].active == 0 then self.qCompText = "Need Photonic Chips" end
    if S.qChips[1].active ~= 0 then
        for _, chip in ipairs(S.qChips) do q = q + chip.value end
        local qq = ceil(q * 360)
        local buffer = (S.memory * 1000) - S.standardOps
        local damper = (S.tempOps / 100) + 5
        if qq > buffer then
            S.tempOps = S.tempOps + ceil(div(qq, damper)) - buffer
            qq = buffer
            S.opFade = .01
            S.opFadeTimer = 0
        end
        S.standardOps = S.standardOps + qq
        self.qCompText = "qOps: " .. Workshop.formatWithCommas(ceil(q * 360))
    end
end

-- Intervals --------------------------------------------------------------

-- main.js:1617, every 100 ms: investment risk and portfolio totals.
function Game:portfolioInterval()
    local S = self.S
    local investStrat = self.selects.investStrat.value
    if investStrat == "low" then
        S.riskiness = 7
    elseif investStrat == "med" then
        S.riskiness = 5
    else
        S.riskiness = 1
    end
    S.m = 0
    for i = 1, S.portfolioSize do S.m = S.m + S.stocks[i].total end
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
        if self.draw("main.js:1490:18") < .25 then self:createStock(budget) end
    end
end

-- main.js:1673, every 2.5 seconds: stock sales and updates.
function Game:stockSellInterval()
    local S = self.S
    S.sellDelay = S.sellDelay + 1
    if S.portfolioSize > 0 and S.sellDelay >= 5 and self.draw("main.js:1677:47") <= .3 and S.humanFlag == 1 then
        self:sellStock()
        S.sellDelay = 0
    end
    if S.portfolioSize > 0 and S.humanFlag == 1 then self:updateStocks() end
end

-- main.js:4188, every 10 ms.
function Game:mainLoop()
    local S = self.S
    S.ticks = S.ticks + 1
    self:milestoneCheck()
    self:buttonUpdate()
    if S.compFlag == 1 then self:calculateOperations() end
    if S.humanFlag == 1 then self:calculateTrust() end
    if S.qFlag == 1 then self:quantumCompute() end
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

    if S.investmentEngineFlag == 1 then self:stockReport() end
    if S.humanFlag == 1 and S.wireBuyerFlag == 1 and S.wireBuyerStatus == 1 and S.wire <= 1 then
        self:buyWire()
    end
    if S.probeCount >= 1 then self:exploreUniverse() end -- Sim/Space.lua
    self:planetaryTick() -- Sim/Planet.lua

    local fbst = 1
    if S.factoryBoost > 1 then fbst = S.factoryBoost * S.factoryLevel end
    if S.dismantle < 4 then
        self:clipClick(S.powMod * fbst * (floor(S.factoryLevel) * S.factoryRate))
    end
    if S.spaceFlag == 1 then self:probeTick() end

    if S.dismantle < 4 then
        self:clipClick(S.clipperBoost * (S.clipmakerLevel / 100))
        self:clipClick(S.megaClipperBoost * (S.megaClipperLevel * 5))
    end

    if S.humanFlag == 1 then
        S.marketing = (pow(1.1, (S.marketingLvl - 1)))
        S.demand = (((div(.8, S.margin)) * S.marketing * S.marketingEffectiveness) * S.demandBoost)
        S.demand = S.demand + ((S.demand / 10) * S.prestigeU)
    end

    if truthy(S.creativityOn) and S.operations >= (S.memory * 1000) then
        self:calculateCreativity()
    end
    self:ending()
end

-- The main loop's ending section (#17), after Reject: the end timers that unlock
-- each dismantling, the photonic chips at rest and the wire they release, and the
-- closing credits once memory is gone and the last wire is used. The panels it
-- hides are presentation.
local creditWire = { [10] = true, [60] = true, [100] = true, [130] = true, [150] = true, [160] = true,
    [165] = true, [169] = true, [172] = true, [174] = true }
local credits = {
    { 500, 15, "Universal Paperclips" },
    { 600, 16, "a game by Frank Lantz" },
    { 700, 17, "combat programming by Bennett Foddy" },
    { 800, 18, "'Riversong' by Tonto's Expanding Headband used by kind permission of Malcolm Cecil" },
    -- "&#169; ..." through innerHTML reads back as the copyright sign.
    { 900, 19, "\194\169 2017 Everybody House Games" },
}
function Game:ending()
    local S = self.S
    if S.dismantle >= 5 then
        for _, chip in ipairs(S.qChips) do chip.value = .5 end
        if creditWire[S.endTimer4] then S.wire = S.wire + 1 end
    end
    if S.project148.flag == 1 then S.endTimer1 = S.endTimer1 + 1 end
    if S.project211.flag == 1 then S.endTimer2 = S.endTimer2 + 1 end
    if S.project212.flag == 1 then S.endTimer3 = S.endTimer3 + 1 end
    if S.project213.flag == 1 then S.endTimer4 = S.endTimer4 + 1 end
    if S.project215.flag == 1 then S.endTimer5 = S.endTimer5 + 1 end
    if S.project216.flag == 1 and S.wire == 0 then S.endTimer6 = S.endTimer6 + 1 end
    for _, credit in ipairs(credits) do
        if S.endTimer6 >= credit[1] and S.milestoneFlag == credit[2] then
            self:displayMessage(credit[3]) -- the first also plays the threnody (audio)
            S.milestoneFlag = S.milestoneFlag + 1
        end
    end
end

-- main.js:4564, every 100 ms: wire price, sales, revenue and auto-save.
function Game:slowLoop()
    local S = self.S
    self:adjustWirePrice()
    if S.humanFlag == 1 then
        if lt(self.draw("main.js:4574:18"), div(S.demand, 100)) then
            self:sellClips(floor(.7 * pow(S.demand, 1.15)))
        end
        S.secTimer = S.secTimer + 1
        if S.secTimer >= 10 then
            self:calculateRev()
            S.secTimer = 0
        end
    end
    S.saveTimer = S.saveTimer + 1
    if S.saveTimer >= 250 then
        self:save()
        S.saveTimer = 0
    end
end

-- save(): the reference serializes the game to browser storage every 25 s without
-- changing any game state. The host persists through game.onSave (#19).
function Game:save()
    if self.onSave then self:onSave() end
end

-- formatWithCommas (main.js), used in messages: Number::toString, expanded e+
-- exponents, then a comma before every three trailing digits of each digit run
-- (the reference regex /(\d)(?=(\d\d\d)+(?!\d))/g).
local function commas(text)
    return (text:gsub("%d+", function(run)
        local out = run:sub(1, (#run - 1) % 3 + 1)
        for i = (#run - 1) % 3 + 2, #run, 3 do out = out .. "," .. run:sub(i, i + 2) end
        return out
    end))
end

function Workshop.formatWithCommas(num, decimal)
    local hasDot = false
    local base = JSMath.toString(num)
    local ePos = base:find("e+", 1, true)
    if ePos then
        local exponent, str = tonumber(base:sub(ePos + 2)), ""
        local whole, fraction = base:sub(1, ePos - 1):match("^(.-)%.(.*)$")
        if whole then
            exponent = exponent - #fraction
            base = whole .. fraction
        end
        while exponent > 0 do
            str = str .. "0"
            exponent = exponent - 1
        end
        -- Without a decimal point the reference keeps "1e+21" itself, so
        -- 1e21 becomes "1e+21,000,...".
        base = base .. str
    end
    local dot = base:find(".", 1, true)
    if dot then hasDot = true end
    if decimal == 0 and #base <= 3 and not hasDot then return base end
    if decimal == nil then decimal = 0 end
    local leftNum = hasDot and base:sub(1, dot - 1) or base
    if decimal == 0 then
        if num <= 999 then return leftNum end
        return commas(leftNum)
    end
    local dec = hasDot and base:sub(dot, dot + decimal) or "."
    while #dec < decimal + 1 do dec = dec .. "0" end
    if num <= 999 then return leftNum .. dec end
    return commas(leftNum) .. dec
end

-- Commands ---------------------------------------------------------------

local clicks = {
    btnMakePaperclip = function(game) game:clipClick(1) end,
    btnBuyWire = Game.buyWire,
    btnToggleWireBuyer = Game.toggleWireBuyer,
    btnMakeClipper = Game.makeClipper,
    btnExpandMarketing = Game.buyAds,
    btnLowerPrice = Game.lowerPrice,
    btnRaisePrice = Game.raisePrice,
    btnMakeMegaClipper = Game.makeMegaClipper,
    btnAddProc = Game.addProc,
    btnAddMem = Game.addMem,
    btnQcompute = Game.qComp,
}

Workshop.clicks = clicks

-- Adds an option; with no option selected, the first one becomes selected (HTML
-- selectedness setting, measured as native_select_probe).
function Game:addOption(id, value)
    local select = self.selects[id]
    select.options[#select.options + 1] = value
    if select.value == "" then select.value = select.options[1] end
end

-- Setting a select to a value without a matching option leaves it empty, as in
-- the browser. A range input sanitizes the value (and keeps its number).
function Game:setValue(id, value)
    local range = self.ranges[id]
    if range then
        range.value = range.sanitize(value)
        range.number = JSMath.toNumber(range.value)
        return
    end
    local select = self.selects[id]
    if not select then Unported("value control " .. tostring(id), "a later slice") end
    select.value = ""
    for _, option in ipairs(select.options) do
        if option == value then select.value = value end
    end
end

-- A click on a disabled control has no effect, matching the browser host. A
-- project button runs the project's effect; the host refuses a click on a project
-- button that is not in the document.
function Game:click(id)
    local handler = clicks[id]
    local entry = Workshop.projectById[id]
    if entry or (not handler and tostring(id):match("^projectButton")) then
        -- The host's error for a project button that is not in the document.
        if not (entry and self.projectElements[id]) then error("Unknown clickable ID", 0) end
        handler = entry.effect
    end
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
