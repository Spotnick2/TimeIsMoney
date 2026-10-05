-- The cosmic phase (#14): what runs after Space Exploration sets spaceFlag. Probe
-- design (trust, its eight allocations and maximum trust), probe launches and
-- replication, surveying the universe for matter, hazards, probe-built factories
-- and drones, and value drift. Battles start once drifters pass warTrigger
-- (Sim/Battle.lua, #15). Source identifiers, formulas and statement
-- order follow main.js. Extends Sim/Workshop.lua and Sim/Planet.lua.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop = ns.JSMath, ns.Workshop
local Game, Unported, costPow = Workshop.Game, ns.Unported, Workshop.costPow
local floor = math.floor

-- Math.pow(n, e) for the probe formulas' integer bases (trust levels, hazard
-- allocations): the pinned reference profile's value (Sim/CostPow.lua). 0^e is 0
-- and 1^e is 1 exactly (ECMAScript Math.pow).
local function requireProbeDomain(n, e, formula)
    if n ~= floor(n) or n < 0 or n > ns.CostPow[e].limit then
        Unported("probe formula Math.pow(" .. JSMath.toString(n) .. ", " .. e .. ") for " .. formula ..
            " beyond the verified domain", "#24")
    end
end
local function probePow(n, e)
    if n == 0 then return 0 end
    if n == 1 then return 1 end
    return costPow(n, e)
end

-- main.js / globals.js / combat.js initial values.
local initial = {
    probeXBaseRate = 1750000000000000000, probeRepBaseRate = .00005, partialProbeSpawn = 0,
    probeHazBaseRate = .01, partialProbeHaz = 0, probesLostHaz = 0, probesLostDrift = 0,
    probeFacBaseRate = .000001, probeHarvBaseRate = .000002, probeWireBaseRate = .000002,
    probeDescendents = 0, probeTrust = 0, probeDriftBaseRate = .000001, probeLaunchLevel = 0,
    honor = 0, maxTrust = 20, maxTrustCost = 91117.99, battleFlag = 0,
    attackSpeed = .2, attackSpeedMod = .1, maxBattles = 1, warTrigger = 1000000,
}
-- Integer powers: exact in JSMath.pow.
initial.probeCost = JSMath.pow(10, 17)
initial.totalMatter = JSMath.pow(10, 54) * 30
-- var foundMatter = availableMatter (globals.js, at load).
initial.foundMatter = Workshop.initial.availableMatter
initial.probeTrustCost = floor(probePow(1, "1.47") * 500)
for key, value in pairs(initial) do Workshop.initial[key] = value end

-- 999999999999999999999999999999999999999999999999 is the double 10^48.
local PROBE_CAP = JSMath.pow(10, 48)

local allocations = { "Speed", "Nav", "Rep", "Haz", "Fac", "Harv", "Wire", "Combat" }
for _, name in ipairs(allocations) do
    Workshop.buttons[#Workshop.buttons + 1] = "btnRaiseProbe" .. name
    Workshop.buttons[#Workshop.buttons + 1] = "btnLowerProbe" .. name
end
for _, id in ipairs({ "btnIncreaseProbeTrust", "btnIncreaseMaxTrust", "btnMakeProbe" }) do
    Workshop.buttons[#Workshop.buttons + 1] = id
end

-- buttonUpdate's probe controls, updated in every phase. btnLowerProbeHaz is
-- reached through the browser's named access to element IDs, the same element.
Workshop.buttonUpdates[#Workshop.buttonUpdates + 1] = function(game, S, disabled)
    disabled.btnIncreaseMaxTrust = S.honor < S.maxTrustCost
    disabled.btnMakeProbe = S.unusedClips < S.probeCost
end

-- After buttonUpdate recomputes probeUsedTrust.
Workshop.lateButtonUpdates[#Workshop.lateButtonUpdates + 1] = function(game, S, disabled)
    disabled.btnIncreaseProbeTrust = S.yomi < S.probeTrustCost or S.probeTrust >= S.maxTrust
    local spare = S.probeTrust - S.probeUsedTrust < 1
    for _, name in ipairs(allocations) do
        disabled["btnRaiseProbe" .. name] = spare
        disabled["btnLowerProbe" .. name] = S["probe" .. name] < 1
    end
end

-- Probe design ------------------------------------------------------------------

function Game:increaseProbeTrust()
    local S = self.S
    if S.yomi >= S.probeTrustCost and S.probeTrust < S.maxTrust then
        -- The next cost's base, checked before anything changes.
        requireProbeDomain(S.probeTrust + 2, "1.47", "the probe trust cost")
        S.yomi = S.yomi - S.probeTrustCost
        S.probeTrust = S.probeTrust + 1
        S.probeTrustCost = floor(probePow(S.probeTrust + 1, "1.47") * 500)
        self:displayMessage("WARNING: Risk of value drift increased")
    end
end

function Game:increaseMaxTrust()
    local S = self.S
    if S.honor >= S.maxTrustCost then
        S.honor = S.honor - S.maxTrustCost
        S.maxTrust = S.maxTrust + 10
        self:displayMessage("Maximum trust increased, probe design space expanded")
    end
end

-- raiseProbeX needs unused trust; lowerProbeX a nonzero allocation. Speed also
-- moves attackSpeed (used by battles, #15).
for _, name in ipairs(allocations) do
    local key = "probe" .. name
    Game["raiseProbe" .. name] = function(self)
        local S = self.S
        if S.probeUsedTrust < S.probeTrust then
            if name == "Speed" then S.attackSpeed = S.attackSpeed + S.attackSpeedMod end
            S[key] = S[key] + 1
        end
    end
    Game["lowerProbe" .. name] = function(self)
        local S = self.S
        if S[key] > 0 then
            if name == "Speed" then S.attackSpeed = S.attackSpeed - S.attackSpeedMod end
            S[key] = S[key] - 1
        end
    end
end

function Game:makeProbe()
    local S = self.S
    if S.unusedClips > S.probeCost then
        S.unusedClips = S.unusedClips - S.probeCost
        S.probeLaunchLevel = S.probeLaunchLevel + 1
        S.probeCount = S.probeCount + 1
    end
end

-- Probe functions -----------------------------------------------------------------

function Game:spawnProbes()
    local S = self.S
    local nextGen = S.probeCount * S.probeRepBaseRate * S.probeRep
    if S.probeCount >= PROBE_CAP then nextGen = 0 end
    -- Partial spawn: early slow growth.
    if nextGen > 0 and nextGen < 1 then
        S.partialProbeSpawn = S.partialProbeSpawn + nextGen
        if S.partialProbeSpawn >= 1 then
            nextGen = 1
            S.partialProbeSpawn = 0
        end
    end
    -- Probes cost clips (probeCost > 0).
    if (nextGen * S.probeCost) > S.unusedClips then
        nextGen = floor(S.unusedClips / S.probeCost)
    end
    S.unusedClips = S.unusedClips - (nextGen * S.probeCost)
    S.probeDescendents = S.probeDescendents + nextGen
    S.probeCount = S.probeCount + nextGen
end

function Game:exploreUniverse()
    local S = self.S
    local xRate = floor(S.probeCount) * S.probeXBaseRate * S.probeSpeed * S.probeNav
    if xRate > S.totalMatter - S.foundMatter then xRate = S.totalMatter - S.foundMatter end
    S.foundMatter = S.foundMatter + xRate
    S.availableMatter = S.availableMatter + xRate
    self.exploreRate = xRate -- mdps (presentation, on the game; never saved)
end

function Game:encounterHazards()
    local S = self.S
    local boost = probePow(S.probeHaz, "1.6")
    local amount = S.probeCount * (S.probeHazBaseRate / ((3 * boost) + 1))
    if S.project129.flag == 1 then amount = .50 * amount end
    if amount < 1 then
        S.partialProbeHaz = S.partialProbeHaz + amount
        if S.partialProbeHaz >= 1 then
            amount = 1
            S.partialProbeHaz = 0
            S.probeCount = S.probeCount - amount
            if S.probeCount < 0 then S.probeCount = 0 end
            S.probesLostHaz = S.probesLostHaz + amount
        end
    else
        if amount > S.probeCount then amount = S.probeCount end
        S.probeCount = S.probeCount - amount
        if S.probeCount < 0 then S.probeCount = 0 end
        S.probesLostHaz = S.probesLostHaz + amount
    end
end

-- spawnFactories / spawnHarvesters / spawnWireDrones: probes build at a fixed clip
-- price each, clamped to whole units the clips can pay for.
local function spawn(game, rate, allocation, price, level)
    local S = game.S
    local amount = S.probeCount * S[rate] * S[allocation]
    if (amount * price) > S.unusedClips then amount = floor(S.unusedClips / price) end
    S.unusedClips = S.unusedClips - (amount * price)
    S[level] = S[level] + amount
end

function Game:spawnFactories() spawn(self, "probeFacBaseRate", "probeFac", 100000000, "factoryLevel") end
function Game:spawnHarvesters() spawn(self, "probeHarvBaseRate", "probeHarv", 2000000, "harvesterLevel") end
function Game:spawnWireDrones() spawn(self, "probeWireBaseRate", "probeWire", 2000000, "wireDroneLevel") end

function Game:drift()
    local S = self.S
    local amount = S.probeCount * S.probeDriftBaseRate * probePow(S.probeTrust, "1.2")
    if amount > S.probeCount then amount = S.probeCount end
    if S.project148.flag == 1 then amount = 0 end
    S.probeCount = S.probeCount - amount
    S.drifterCount = S.drifterCount + amount
    S.probesLostDrift = S.probesLostDrift + amount
end

-- war -> checkForBattles (combat.js): once drifters pass warTrigger, an even chance
-- each tick to start a battle (at most maxBattles at once).
function Game:war()
    local S = self.S
    if S.drifterCount > S.warTrigger and S.probeCount > 0 and #S.battles < S.maxBattles then
        local r = (self.draw("combat.js:57:23") * 100)
        if r >= 50 then
            if S.battleFlag == 0 then S.battleFlag = 1 end
            ns.Battle.createBattle(S, self.draw)
        end
    end
end

-- The main loop's probe section (spaceFlag == 1). Like every stop inside a tick, a
-- stop here halts the simulation: the tick's earlier steps have run (only commands
-- guarantee a stop before any change). The formula domains are checked first.
function Game:probeTick()
    local S = self.S
    requireProbeDomain(S.probeHaz, "1.6", "hazards")
    requireProbeDomain(S.probeTrust, "1.2", "drift")
    if S.probeCount < 0 then S.probeCount = 0 end
    self:encounterHazards()
    self:spawnFactories()
    self:spawnHarvesters()
    self:spawnWireDrones()
    self:spawnProbes()
    self:drift()
    self:war()
end

-- Controls ------------------------------------------------------------------------

local clicks = Workshop.clicks
clicks.btnIncreaseProbeTrust = Game.increaseProbeTrust
clicks.btnIncreaseMaxTrust = Game.increaseMaxTrust
clicks.btnMakeProbe = Game.makeProbe
for _, name in ipairs(allocations) do
    clicks["btnRaiseProbe" .. name] = Game["raiseProbe" .. name]
    clicks["btnLowerProbe" .. name] = Game["lowerProbe" .. name]
end

return Workshop
