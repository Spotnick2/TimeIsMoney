-- Planetary phase (#11, #12): what runs after Release the HypnoDrones, before space.
-- Harvester drones, wire drones and clip factories with their costs, the matter
-- pools (available -> acquired -> wire), solar farms and battery towers with power
-- supply, demand, storage and momentum, and the swarm's per-tick state (boredom,
-- disorganization, status). The work/think slider, gifts and swarm actions are #13;
-- space is #14. Source identifiers, formulas and statement order follow main.js.
-- Extends Sim/Workshop.lua; Sim/CostPow.lua loads first.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop, CostPow = ns.JSMath, ns.Workshop, ns.CostPow
local Game, Unported = Workshop.Game, ns.Unported
local floor, max, min = math.floor, math.max, math.min

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
local function costPow(n, e)
    local domain = CostPow[e]
    if n ~= floor(n) or n < 1 or n > domain.limit then
        Unported("building cost Math.pow(" .. JSMath.toString(n) .. ", " .. e .. ") beyond the verified domain", "#24")
    end
    local fix = domain.fixes[n]
    if fix then return JSMath.fromWords(fix[1], fix[2]) end
    return JSMath.pow(n, tonumber(e))
end
Workshop.costPow = costPow

-- Stops before any change when a purchase or price update could need a cost beyond
-- the domain (the last base is level + amount, then the lookahead sums).
local function requireDomain(e, base)
    if base > CostPow[e].limit then
        Unported("building cost Math.pow(" .. base .. ", " .. e .. ") beyond the verified domain", "#24")
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

-- Sum of `count` consecutive costs from `from`, in source order.
local function priceSum(from, count, e, scale)
    local p = 0
    for i = 0, count - 1 do p = p + costPow(from + i, e) * scale end
    return p
end

function Game:updateDronePrices()
    local S = self.S
    requireDomain("2.25", max(S.harvesterLevel, S.wireDroneLevel) + 1000)
    S.p10h = priceSum(S.harvesterLevel + 1, 10, "2.25", 1000000)
    S.p100h = priceSum(S.harvesterLevel + 1, 100, "2.25", 1000000)
    S.p1000h = priceSum(S.harvesterLevel + 1, 1000, "2.25", 1000000)
    S.p10w = priceSum(S.wireDroneLevel + 1, 10, "2.25", 1000000)
    S.p100w = priceSum(S.wireDroneLevel + 1, 100, "2.25", 1000000)
    S.p1000w = priceSum(S.wireDroneLevel + 1, 1000, "2.25", 1000000)
    S.x = 1000
end

-- makeHarvester / makeWireDrone: buy up to `amount`, one at a time, each at the
-- cost recomputed after the previous purchase.
local function makeDrones(game, amount, level, cost, bill)
    local S = game.S
    requireDomain("2.25", S[level] + amount + 1000)
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
    requireDomain("2.78", S.farmLevel + 100)
    requireDomain("2.54", S.batteryLevel + 100)
    S.p10f = priceSum(S.farmLevel + 1, 10, "2.78", 100000000)
    S.p100f = priceSum(S.farmLevel + 1, 100, "2.78", 100000000)
    S.p10b = priceSum(S.batteryLevel + 1, 10, "2.54", 10000000)
    S.p100b = priceSum(S.batteryLevel + 1, 100, "2.54", 10000000)
    S.x = 100
end

local function makePower(game, amount, e, scale, level, cost, bill)
    local S = game.S
    requireDomain(e, S[level] + amount + 100)
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

-- updateSwarm's per-tick state. The slider (read once Swarm Computing sets
-- swarmFlag), gifts and the Active status that generates them are #13.
function Game:updateSwarm()
    local S, disabled = self.S, self.disabled
    if JSMath.isNaN(S.swarmGifts) or S.swarmGifts < 0 then S.swarmGifts = 0 end
    if S.swarmFlag == 1 then Unported("the swarm work/think slider", "#13") end
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
    -- giftCountdown changes only while the swarm is Active, which needs swarmFlag.
    if S.giftCountdown <= 0 then Unported("swarm gifts", "#13") end
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
    if S.swarmStatus == 0 then Unported("swarm gift generation", "#13") end
end

-- Matter ---------------------------------------------------------------------

function Game:acquireMatter()
    local S = self.S
    if S.availableMatter > 0 then
        local dbsth = 1
        if S.droneBoost > 1 then dbsth = S.droneBoost * floor(S.harvesterLevel) end
        local mtr = S.powMod * dbsth * floor(S.harvesterLevel) * S.harvesterRate
        mtr = mtr * ((200 - S.sliderPos) / 100)
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
        a = a * ((200 - S.sliderPos) / 100)
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
clicks.btnSynchSwarm = function() Unported("synchSwarm", "#13") end
clicks.btnEntertainSwarm = function() Unported("entertainSwarm", "#13") end

return Workshop
