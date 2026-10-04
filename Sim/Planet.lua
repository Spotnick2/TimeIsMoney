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
local isNaN, toNumber = JSMath.isNaN, JSMath.toNumber

-- JavaScript `x <= 0`: false for NaN (WoW's Lua compares NaN as true).
local function atMostZero(x) return not isNaN(x) and x <= 0 end

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
-- sanitizes as the host does: HTML decimal syntax only, otherwise the midpoint;
-- clamped, then rounded with ties upward. Its value stays a string.
local function sanitizeSlider(value)
    value = tostring(value)
    local mantissa, exponent = value:match("^(%-?%d*%.?%d*)(.*)$")
    local valid = mantissa and mantissa:find("%d") and not mantissa:find("%.$")
        and (exponent == "" or exponent:find("^[eE][+-]?%d+$")) and true or false
    local n = valid and toNumber(value) or JSMath.NAN
    if isNaN(n) or n == math.huge or n == -math.huge then n = 100 end
    return JSMath.toString(JSMath.round(max(0, min(200, n))))
end
Workshop.sanitizeSlider = sanitizeSlider
Workshop.setups[#Workshop.setups + 1] = function(game)
    game.selects.slider = { value = "0", sanitize = sanitizeSlider }
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
-- it differs from JSMath.pow. Beyond the compared domain the reference value is
-- unknown, so the slice stops.
-- A cost is a pure function of its integer base, so computed values are kept
-- (the pure-Lua pow is slow and the price sums revisit the same bases).
local memo = { ["2.25"] = {}, ["2.54"] = {}, ["2.78"] = {} }
local function costPow(n, e)
    local domain = CostPow[e]
    if n ~= floor(n) or n < 1 or n > domain.limit then
        Unported("building cost Math.pow(" .. JSMath.toString(n) .. ", " .. e .. ") beyond the verified domain", "#24")
    end
    local value = memo[e][n]
    if value == nil then
        local fix = domain.fixes[n]
        value = fix and JSMath.fromWords(fix[1], fix[2]) or JSMath.pow(n, tonumber(e))
        memo[e][n] = value
    end
    return value
end
Workshop.costPow = costPow

-- Every cost base the price updates reach from the given levels: each drone level
-- + 1000 (purchase loops stay within that), each farm and battery level + 100.
-- Purchases and reboots call it first with the levels after the operation, so a
-- stop (#24) always comes before any change.
local function requirePriceDomains(S, levels)
    local function level(name) return levels and levels[name] or S[name] end
    for _, check in ipairs({
        { "2.25", level("harvesterLevel") + 1000 }, { "2.25", level("wireDroneLevel") + 1000 },
        { "2.78", level("farmLevel") + 100 }, { "2.54", level("batteryLevel") + 100 },
    }) do
        if check[2] > CostPow[check[1]].limit then
            Unported("building cost Math.pow(" .. check[2] .. ", " .. check[1] .. ") beyond the verified domain", "#24")
        end
    end
end

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
    requirePriceDomains(S)
    S.p10h, S.p100h, S.p1000h = priceSums(S.harvesterLevel + 1, 1000, "2.25", 1000000)
    S.p10w, S.p100w, S.p1000w = priceSums(S.wireDroneLevel + 1, 1000, "2.25", 1000000)
    S.x = 1000
end

-- makeHarvester / makeWireDrone: buy up to `amount`, one at a time, each at the
-- cost recomputed after the previous purchase.
local function makeDrones(game, amount, level, cost, bill)
    local S = game.S
    requirePriceDomains(S, { [level] = S[level] + amount })
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
    requirePriceDomains(S, { harvesterLevel = 0 })
    S.harvesterLevel = 0
    S.unusedClips = S.unusedClips + S.harvesterBill
    S.harvesterBill = 0
    self:updateDronePrices()
    S.harvesterCost = 1000000
end

function Game:wireDroneReboot()
    local S = self.S
    requirePriceDomains(S, { wireDroneLevel = 0 })
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
    requirePriceDomains(S)
    local _
    S.p10f, _, S.p100f = priceSums(S.farmLevel + 1, 100, "2.78", 100000000)
    S.p10b, _, S.p100b = priceSums(S.batteryLevel + 1, 100, "2.54", 10000000)
    S.x = 100
end

local function makePower(game, amount, e, scale, level, cost, bill)
    local S = game.S
    requirePriceDomains(S, { [level] = S[level] + amount })
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
    requirePriceDomains(S, { farmLevel = 0 })
    S.farmLevel = 0
    S.unusedClips = S.unusedClips + S.farmBill
    S.farmBill = 0
    self:updatePowPrices()
    S.farmCost = 10000000
end

function Game:batteryReboot()
    local S = self.S
    requirePriceDomains(S, { batteryLevel = 0 })
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
    if S.swarmFlag == 1 then S.sliderPos = self.selects.slider.value end
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
    if atMostZero(S.giftCountdown) then
        S.nextGift = JSMath.round((JSMath.log10(d)) * toNumber(S.sliderPos) / 100)
        if atMostZero(S.nextGift) then S.nextGift = 1 end
        S.swarmGifts = S.swarmGifts + S.nextGift
        if S.milestoneFlag < 15 then
            self:displayMessage("The swarm has generated a gift of " .. JSMath.toString(S.nextGift) ..
                " additional computational capacity")
        end
        S.giftBits = 0
    end
    if S.powMod == 0 then S.swarmStatus = 6 else S.swarmStatus = 0 end
    if S.spaceFlag == 1 then Unported("the swarm in space", "#14") end
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
        S.giftBitGenerationRate = JSMath.log(d) * (toNumber(S.sliderPos) / 100)
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

function Game:acquireMatter()
    local S = self.S
    if S.availableMatter > 0 then
        local dbsth = 1
        if S.droneBoost > 1 then dbsth = S.droneBoost * floor(S.harvesterLevel) end
        local mtr = S.powMod * dbsth * floor(S.harvesterLevel) * S.harvesterRate
        mtr = mtr * ((200 - toNumber(S.sliderPos)) / 100)
        if mtr > S.availableMatter then mtr = S.availableMatter end
        S.availableMatter = S.availableMatter - mtr
        S.acquiredMatter = S.acquiredMatter + mtr
    end
end

function Game:processMatter()
    local S = self.S
    if S.acquiredMatter > 0 then
        local dbstw = 1
        if S.droneBoost > 1 then dbstw = S.droneBoost * floor(S.wireDroneLevel) end
        local a = S.powMod * dbstw * floor(S.wireDroneLevel) * S.wireDroneRate
        a = a * ((200 - toNumber(S.sliderPos)) / 100)
        if a > S.acquiredMatter then a = S.acquiredMatter end
        S.acquiredMatter = S.acquiredMatter - a
        S.wire = S.wire + a
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
