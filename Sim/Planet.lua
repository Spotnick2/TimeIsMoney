-- Planetary phase (#11, #12, #13): what runs after Release the HypnoDrones, before
-- space. Harvester drones, wire drones and clip factories with their costs, the
-- matter pools (available -> acquired -> wire), solar farms and battery towers with
-- power supply, demand, storage and momentum, and the swarm: the work/think slider,
-- gifts, boredom and disorganization with their recovery actions, and status. Space
-- is #14. Source identifiers, formulas and statement order follow main.js.
-- Extends Sim/Workshop.lua; Sim/CostPow.lua loads first.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop, CostPow = ns.JSMath, ns.Workshop, ns.CostPow
local Game, Unported = Workshop.Game, ns.Unported
local floor, max, min = math.floor, math.max, math.min
local isNaN, toNumber, le, div = JSMath.isNaN, JSMath.toNumber, JSMath.le, JSMath.div

-- globals.js / main.js initial values.
local initial = {
    harvesterLevel = 0, wireDroneLevel = 0, harvesterCost = 1000000, wireDroneCost = 1000000,
    factoryCost = 100000000, harvesterBill = 0, wireDroneBill = 0, factoryBill = 0,
    maxFactoryLevel = 0, maxDroneLevel = 0, harvesterRate = 26180337, wireDroneRate = 16180339,
    droneBoost = 1, acquiredMatter = 0, sliderPos = 0,
    farmLevel = 0, farmCost = 10000000, farmBill = 0, batteryLevel = 0, batteryCost = 1000000,
    batteryBill = 0, storedPower = 0, farmRate = 50, batterySize = 10000, dronePowerRate = 1,
    factoryPowerRate = 200, momentum = 0,
    factoryFlag = 0, harvesterFlag = 0, wireDroneFlag = 0, wireProductionFlag = 0, tothFlag = 0,
    swarmStatus = 7, boredomLevel = 0, boredomFlag = 0, boredomMsg = 0, disorgCounter = 0,
    disorgFlag = 0, disorgMsg = 0, giftPeriod = 125000, giftCountdown = 125000, nextGift = 0,
    giftBits = 0, giftBitGenerationRate = 0, synchCost = 5000, entertainCost = 10000,
    -- Price sums for the multi-buy buttons (updateDronePrices, updatePowPrices).
    p10h = 0, p100h = 0, p1000h = 0, p10w = 0, p100w = 0, p1000w = 0,
    p10f = 0, p100f = 0, p10b = 0, p100b = 0,
    -- The loop variable the reference leaves global (`for (x=0; ...)`).
    x = 0,
}
-- Math.pow(10, 24)*6000: an integer power, exact in JSMath.pow.
initial.availableMatter = JSMath.pow(10, 24) * 6000
for key, value in pairs(initial) do Workshop.initial[key] = value end

-- The swarm slider (index2.html: range 0..200, step 1, value "0"). Setting it
-- sanitizes as the host does (Tools/reference/dom.cjs): the HTML decimal syntax
-- ^-?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$ or else the midpoint; clamped,
-- then rounded with ties upward. Its value stays a string; the number is kept
-- beside it so the main loop does not parse it every tick.
local function decimal(text)
    local body, exponent = text:match("^%-?([%d%.]+)(.*)$")
    if not body then return false end
    local mantissa = body:match("^%d+$") or body:match("^%d+%.%d+$") or body:match("^%.%d+$")
    return mantissa ~= nil and (exponent == "" or exponent:match("^[eE][+-]?%d+$") ~= nil)
end
local function sanitizeSlider(value)
    value = tostring(value)
    local n = decimal(value) and toNumber(value) or JSMath.NAN
    if isNaN(n) or n == math.huge or n == -math.huge then n = 100 end
    return JSMath.toString(JSMath.round(max(0, min(200, n))))
end
Workshop.sanitizeSlider = sanitizeSlider
-- Range controls by id, with their sanitizer (a restored game rebuilds them, #19).
Workshop.rangeControls = Workshop.rangeControls or {}
Workshop.rangeControls.slider = sanitizeSlider
Workshop.setups[#Workshop.setups + 1] = function(game)
    game.ranges.slider = { value = "0", number = 0, sanitize = sanitizeSlider }
end

-- sliderPos as a number: 0 until Swarm Computing, then the slider's string.
local function sliderNumber(game)
    local v, slider = game.S.sliderPos, game.ranges.slider
    if type(v) == "number" then return v end
    if v == slider.value then return slider.number end
    return toNumber(v)
end

for _, id in ipairs({
    "btnMakeFactory", "btnHarvesterReboot", "btnWireDroneReboot", "btnFactoryReboot",
    "btnMakeHarvester", "btnHarvesterx10", "btnHarvesterx100", "btnHarvesterx1000",
    "btnMakeWireDrone", "btnWireDronex10", "btnWireDronex100", "btnWireDronex1000",
    "btnMakeFarm", "btnMakeBattery", "btnFarmReboot", "btnBatteryReboot",
    "btnFarmx10", "btnFarmx100", "btnBatteryx10", "btnBatteryx100",
    "btnSynchSwarm", "btnEntertainSwarm",
}) do Workshop.buttons[#Workshop.buttons + 1] = id end

-- Building costs ------------------------------------------------------------

-- Math.pow(n, e) for a cost: the reference profile's value (Sim/CostPow.lua) where
-- it differs from JSMath.pow.
-- A cost is a pure function of its integer base, so computed values are kept
-- (the pure-Lua pow is slow and the price sums revisit the same bases). Beyond the
-- table the memo is bounded: it starts over after MEMO_BEYOND entries, since levels
-- only move forward and the sums look at most 1,000 bases ahead.
local memo, beyond, MEMO_BEYOND = {}, {}, 4096
for e, domain in pairs(CostPow) do
    if type(domain) == "table" then memo[e], beyond[e] = {}, { count = 0 } end
end
-- Inside the verified domain (integer bases up to the table's limit) the value is
-- the pinned reference profile's, exactly. Beyond it, or for a fractional base
-- (probes build fractional drone levels in space), it is the correctly rounded
-- pow: within one binary64 step of the reference's platform pow, which no portable
-- implementation reproduces (#24, owner decision 2026-10-06; docs/reference/WORKSHOP.md).
-- Only integer bases are memoized: fractional levels change every tick.
local function costPow(n, e)
    local domain = CostPow[e]
    if n ~= floor(n) then return JSMath.pow(n, tonumber(e)) end
    local inside = n >= 1 and n <= domain.limit
    local cache = inside and memo[e] or beyond[e]
    local value = cache[n]
    if value == nil then
        local fix = inside and domain.fixes[n]
        value = fix and JSMath.fromWords(fix[1], fix[2]) or JSMath.pow(n, tonumber(e))
        if not inside then
            if cache.count >= MEMO_BEYOND then
                cache = { count = 0 }
                beyond[e] = cache
            end
            cache.count = cache.count + 1
        end
        cache[n] = value
    end
    return value
end
Workshop.costPow = costPow


-- updateUpgrades only writes presentation (the next upgrade thresholds).

function Game:makeFactory()
    local S = self.S
    if S.unusedClips >= S.factoryCost then
        S.unusedClips = S.unusedClips - S.factoryCost
        S.factoryBill = S.factoryBill + S.factoryCost
        S.factoryLevel = S.factoryLevel + 1
        local fcmod = 1
        local level = S.factoryLevel
        if level > 0 and level < 8 then
            fcmod = 11 - level
        elseif level > 7 and level < 13 then
            fcmod = 2
        elseif level > 12 and level < 20 then
            fcmod = 1.5
        elseif level > 19 and level < 39 then
            fcmod = 1.25
        elseif level > 38 and level < 79 then
            fcmod = 1.15
        elseif level > 78 then
            fcmod = 1.10
        end
        if S.factoryLevel > S.maxFactoryLevel then S.maxFactoryLevel = S.factoryLevel end
        S.factoryCost = S.factoryCost * fcmod
    end
end

-- Sums of the first 10, 100 and (count = 1000) costs from `from`, in source order.
-- The reference recomputes each sum from 0; one running sum reaches the same
-- partial values, because the same additions happen in the same order.
local function priceSums(from, count, e, scale)
    local p, p10, p100 = 0, nil, nil
    for i = 0, count - 1 do
        p = p + costPow(from + i, e) * scale
        if i == 9 then p10 = p elseif i == 99 then p100 = p end
    end
    return p10, p100, p
end

function Game:updateDronePrices()
    local S = self.S
    S.p10h, S.p100h, S.p1000h = priceSums(S.harvesterLevel + 1, 1000, "2.25", 1000000)
    S.p10w, S.p100w, S.p1000w = priceSums(S.wireDroneLevel + 1, 1000, "2.25", 1000000)
    S.x = 1000
end

-- makeHarvester / makeWireDrone: buy up to `amount`, one at a time, each at the
-- cost recomputed after the previous purchase.
local function makeDrones(game, amount, level, cost, bill)
    local S = game.S
    for _ = 1, amount do
        if S.unusedClips >= S[cost] then
            S.unusedClips = S.unusedClips - S[cost]
            S[bill] = S[bill] + S[cost]
            S[level] = S[level] + 1
            S[cost] = costPow(S[level] + 1, "2.25") * 1000000
        end
    end
    S.x = amount
    if S.harvesterLevel + S.wireDroneLevel > S.maxDroneLevel then
        S.maxDroneLevel = S.harvesterLevel + S.wireDroneLevel
    end
    game:updateDronePrices()
end

function Game:makeHarvester(amount)
    makeDrones(self, amount, "harvesterLevel", "harvesterCost", "harvesterBill")
end

function Game:makeWireDrone(amount)
    makeDrones(self, amount, "wireDroneLevel", "wireDroneCost", "wireDroneBill")
end

function Game:updateDroneButtons()
    local S, disabled = self.S, self.disabled
    disabled.btnMakeHarvester = S.unusedClips < S.harvesterCost
    disabled.btnHarvesterx10 = S.unusedClips < S.p10h
    disabled.btnHarvesterx100 = S.unusedClips < S.p100h
    disabled.btnHarvesterx1000 = S.unusedClips < S.p1000h
    disabled.btnMakeWireDrone = S.unusedClips < S.wireDroneCost
    disabled.btnWireDronex10 = S.unusedClips < S.p10w
    disabled.btnWireDronex100 = S.unusedClips < S.p100w
    disabled.btnWireDronex1000 = S.unusedClips < S.p1000w
end

function Game:harvesterReboot()
    local S = self.S
    S.harvesterLevel = 0
    S.unusedClips = S.unusedClips + S.harvesterBill
    S.harvesterBill = 0
    self:updateDronePrices()
    S.harvesterCost = 1000000
end

function Game:wireDroneReboot()
    local S = self.S
    S.wireDroneLevel = 0
    S.unusedClips = S.unusedClips + S.wireDroneBill
    S.wireDroneBill = 0
    self:updateDronePrices()
    S.wireDroneCost = 1000000
end

function Game:factoryReboot()
    local S = self.S
    S.factoryLevel = 0
    S.unusedClips = S.unusedClips + S.factoryBill
    S.factoryBill = 0
    S.factoryCost = 100000000
end

-- Power ----------------------------------------------------------------------

function Game:updatePowPrices()
    local S = self.S
    local _
    S.p10f, _, S.p100f = priceSums(S.farmLevel + 1, 100, "2.78", 100000000)
    S.p10b, _, S.p100b = priceSums(S.batteryLevel + 1, 100, "2.54", 10000000)
    S.x = 100
end

local function makePower(game, amount, e, scale, level, cost, bill)
    local S = game.S
    for _ = 1, amount do
        if S.unusedClips >= S[cost] then
            S.unusedClips = S.unusedClips - S[cost]
            S[bill] = S[bill] + S[cost]
            S[level] = S[level] + 1
            S[cost] = costPow(S[level] + 1, e) * scale
        end
    end
    S.x = amount
    game:updatePowPrices()
end

function Game:makeFarm(amount)
    makePower(self, amount, "2.78", 100000000, "farmLevel", "farmCost", "farmBill")
end

function Game:makeBattery(amount)
    makePower(self, amount, "2.54", 10000000, "batteryLevel", "batteryCost", "batteryBill")
end

-- The reboots reset to these costs, which differ from the first purchase's
-- formula (farms 1e7, batteries 1e6), as in the reference.
function Game:farmReboot()
    local S = self.S
    S.farmLevel = 0
    S.unusedClips = S.unusedClips + S.farmBill
    S.farmBill = 0
    self:updatePowPrices()
    S.farmCost = 10000000
end

function Game:batteryReboot()
    local S = self.S
    S.batteryLevel = 0
    S.unusedClips = S.unusedClips + S.batteryBill
    S.batteryBill = 0
    self:updatePowPrices()
    S.storedPower = 0
    S.batteryCost = 1000000
end

-- updatePower: supply from farms, demand from drones and factories, surplus into
-- storage, shortfall from storage, then powMod (the production multiplier).
function Game:updatePower()
    local S, disabled = self.S, self.disabled
    if not (S.humanFlag == 0 and S.spaceFlag == 0) then return end
    local supply = S.farmLevel * S.farmRate / 100
    local dDemand = (S.harvesterLevel * S.dronePowerRate / 100) + (S.wireDroneLevel * S.dronePowerRate / 100)
    local fDemand = (S.factoryLevel * S.factoryPowerRate / 100)
    local demand = dDemand + fDemand
    local nuSupply, xsDemand, xsSupply = 0, 0, 0
    local cap = S.batteryLevel * S.batterySize
    if supply >= demand then
        xsSupply = supply - demand
        if S.storedPower < cap then
            if xsSupply > cap - S.storedPower then xsSupply = cap - S.storedPower end
            S.storedPower = S.storedPower + xsSupply
        end
        if S.powMod < 1 then S.powMod = 1 end
        if S.momentum == 1 then S.powMod = S.powMod + .0005 end
    elseif supply < demand then
        -- demand > supply >= 0 here, so the divisions are by a positive number.
        xsDemand = demand - supply
        if S.storedPower > 0 then
            if S.storedPower >= xsDemand then
                if S.momentum == 1 then S.powMod = S.powMod + .0005 end
                S.storedPower = S.storedPower - xsDemand
            elseif S.storedPower < xsDemand then
                xsDemand = xsDemand - S.storedPower
                S.storedPower = 0
                nuSupply = supply - xsDemand
                S.powMod = nuSupply / demand
            end
        elseif S.storedPower <= 0 then
            S.powMod = supply / demand
        end
    end
    disabled.btnMakeFarm = S.unusedClips < S.farmCost
    disabled.btnMakeBattery = S.unusedClips < S.batteryCost
    disabled.btnFarmReboot = S.farmLevel < 1
    disabled.btnBatteryReboot = S.batteryLevel < 1
    disabled.btnFarmx10 = S.unusedClips < S.p10f
    disabled.btnFarmx100 = S.unusedClips < S.p100f
    disabled.btnBatteryx10 = S.unusedClips < S.p10b
    disabled.btnBatteryx100 = S.unusedClips < S.p100b
end

-- Swarm ----------------------------------------------------------------------

-- updateSwarm: the slider (read once Swarm Computing sets swarmFlag), boredom,
-- disorganization, gifts and status.
function Game:updateSwarm()
    local S, disabled = self.S, self.disabled
    if isNaN(S.swarmGifts) or S.swarmGifts < 0 then S.swarmGifts = 0 end
    if S.swarmFlag == 1 then S.sliderPos = self.ranges.slider.value end
    disabled.btnSynchSwarm = S.yomi < S.synchCost
    disabled.btnEntertainSwarm = S.creativity < S.entertainCost
    if S.availableMatter == 0 and (S.harvesterLevel + S.wireDroneLevel) >= 1 then
        S.boredomLevel = S.boredomLevel + 1
    elseif S.availableMatter > 0 and S.boredomLevel > 0 then
        S.boredomLevel = S.boredomLevel - 1
    end
    if S.boredomLevel >= 30000 then
        S.boredomFlag = 1
        S.boredomLevel = 0
        if S.boredomMsg == 0 then
            self:displayMessage("No matter to harvest. Inactivity has caused the Swarm to become bored")
            S.boredomMsg = 1
        end
    end
    -- Both operands are at least 1.
    local droneRatio = max(S.harvesterLevel + 1, S.wireDroneLevel + 1) / min(S.harvesterLevel + 1, S.wireDroneLevel + 1)
    if droneRatio < 1.5 and S.disorgCounter > 1 then
        S.disorgCounter = S.disorgCounter - .01
    elseif droneRatio > 1.5 then
        local x = droneRatio / 10000
        if x > .01 then x = .01 end
        S.disorgCounter = S.disorgCounter + x
    end
    if S.disorgCounter >= 100 then
        S.disorgFlag = 1
        if S.disorgMsg == 0 then
            self:displayMessage("Imbalance between Harvester and Wire Drone levels has disorganized the Swarm")
            S.disorgMsg = 1
        end
    end
    local d = floor(S.harvesterLevel + S.wireDroneLevel)
    -- giftCountdown is recomputed only while the swarm is Active, so after a gift it
    -- stays at or below 0, and the gift repeats every tick, until the swarm is
    -- Active again (reference behavior).
    -- With no drones and the slider at 0, log10(0) * 0 is NaN: the reference carries
    -- it into nextGift and swarmGifts (reset to 0 next tick), so nothing divides it
    -- natively.
    if le(S.giftCountdown, 0) then
        S.nextGift = JSMath.round(div((JSMath.log10(d)) * sliderNumber(self), 100))
        if le(S.nextGift, 0) then S.nextGift = 1 end
        S.swarmGifts = S.swarmGifts + S.nextGift
        if S.milestoneFlag < 15 then
            self:displayMessage("The swarm has generated a gift of " .. JSMath.toString(S.nextGift) ..
                " additional computational capacity")
        end
        S.giftBits = 0
    end
    if S.powMod == 0 then S.swarmStatus = 6 else S.swarmStatus = 0 end
    if S.spaceFlag == 1 and S.project130.flag == 0 then S.swarmStatus = 9 end
    if d == 0 then
        S.swarmStatus = 7
    elseif d == 1 then
        S.swarmStatus = 8
    end
    if S.swarmFlag == 0 then S.swarmStatus = 6 end
    if S.boredomFlag == 1 then S.swarmStatus = 3 end
    if S.disorgFlag == 1 then S.swarmStatus = 5 end
    if S.swarmStatus == 0 then
        -- d >= 2 here (0 and 1 have their own statuses), so the log is positive; a
        -- slider at 0 makes the rate 0 and the countdown Infinity.
        S.giftBitGenerationRate = JSMath.log(d) * (sliderNumber(self) / 100)
        S.giftBits = S.giftBits + S.giftBitGenerationRate
        S.giftCountdown = JSMath.div(S.giftPeriod - S.giftBits, S.giftBitGenerationRate)
    end
end

-- Recovery actions. Neither checks its cost; the disabled control does.
function Game:synchSwarm()
    local S = self.S
    S.yomi = S.yomi - S.synchCost
    S.disorgFlag = 0
    S.disorgCounter = 0
    S.disorgMsg = 0
end

function Game:entertainSwarm()
    local S = self.S
    S.creativity = S.creativity - S.entertainCost
    S.entertainCost = S.entertainCost + 10000
    S.boredomFlag = 0
    S.boredomLevel = 0
    S.boredomMsg = 0
end

-- Matter ---------------------------------------------------------------------

-- The rates the reference prints (maps, wpps) are presentation: kept on the game
-- for the window (per tick; 0 when nothing moved), never in the state or the save.
function Game:acquireMatter()
    local S = self.S
    self.matterRate = 0
    if S.availableMatter > 0 then
        local dbsth = 1
        if S.droneBoost > 1 then dbsth = S.droneBoost * floor(S.harvesterLevel) end
        local mtr = S.powMod * dbsth * floor(S.harvesterLevel) * S.harvesterRate
        mtr = mtr * ((200 - sliderNumber(self)) / 100)
        if mtr > S.availableMatter then mtr = S.availableMatter end
        S.availableMatter = S.availableMatter - mtr
        S.acquiredMatter = S.acquiredMatter + mtr
        self.matterRate = mtr
    end
end

function Game:processMatter()
    local S = self.S
    self.wireRate = 0
    if S.acquiredMatter > 0 then
        local dbstw = 1
        if S.droneBoost > 1 then dbstw = S.droneBoost * floor(S.wireDroneLevel) end
        local a = S.powMod * dbstw * floor(S.wireDroneLevel) * S.wireDroneRate
        a = a * ((200 - sliderNumber(self)) / 100)
        if a > S.acquiredMatter then a = S.acquiredMatter end
        S.acquiredMatter = S.acquiredMatter - a
        S.wire = S.wire + a
        self.wireRate = a
    end
end

-- The main loop's planetary section, between WireBuyer and the factories.
function Game:planetaryTick()
    local S = self.S
    if S.humanFlag == 0 and S.spaceFlag == 0 then self:updateDroneButtons() end
    if S.humanFlag == 0 then
        self:updatePower()
        self:updateSwarm()
        self:acquireMatter()
        self:processMatter()
    end
end

-- buttonUpdate's planetary controls, updated in every phase.
Workshop.buttonUpdates[#Workshop.buttonUpdates + 1] = function(game, S, disabled)
    disabled.btnMakeFactory = S.unusedClips < S.factoryCost
    disabled.btnHarvesterReboot = S.harvesterLevel == 0
    disabled.btnWireDroneReboot = S.wireDroneLevel == 0
    disabled.btnFactoryReboot = S.factoryLevel == 0
end

-- Controls --------------------------------------------------------------------

local clicks = Workshop.clicks
clicks.btnMakeFactory = Game.makeFactory
clicks.btnFactoryReboot = Game.factoryReboot
clicks.btnHarvesterReboot = Game.harvesterReboot
clicks.btnWireDroneReboot = Game.wireDroneReboot
clicks.btnFarmReboot = Game.farmReboot
clicks.btnBatteryReboot = Game.batteryReboot
for id, amount in pairs({ btnMakeHarvester = 1, btnHarvesterx10 = 10, btnHarvesterx100 = 100, btnHarvesterx1000 = 1000 }) do
    clicks[id] = function(game) game:makeHarvester(amount) end
end
for id, amount in pairs({ btnMakeWireDrone = 1, btnWireDronex10 = 10, btnWireDronex100 = 100, btnWireDronex1000 = 1000 }) do
    clicks[id] = function(game) game:makeWireDrone(amount) end
end
for id, amount in pairs({ btnMakeFarm = 1, btnFarmx10 = 10, btnFarmx100 = 100 }) do
    clicks[id] = function(game) game:makeFarm(amount) end
end
for id, amount in pairs({ btnMakeBattery = 1, btnBatteryx10 = 10, btnBatteryx100 = 100 }) do
    clicks[id] = function(game) game:makeBattery(amount) end
end
clicks.btnSynchSwarm = Game.synchSwarm
clicks.btnEntertainSwarm = Game.entertainSwarm

return Workshop
