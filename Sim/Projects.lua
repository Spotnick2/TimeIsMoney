-- Projects (projects.js) through the planetary phase: availability, eligibility,
-- purchase effects, repeatable entries and the first transition (Release the
-- HypnoDrones). Entries follow projects.js registration order; each has the
-- reference trigger and cost and, where the ported phases can buy it, the effect.
-- Projects whose triggers need space, battles or the ending are omitted; they
-- cannot appear yet (see docs/reference/PROJECTS.md). Extends Sim/Workshop.lua.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop = ns.JSMath, ns.Workshop
local Game, Unported, truthy = Workshop.Game, ns.Unported, Workshop.truthy

-- Number.prototype.toLocaleString as the host pins it (en-US), for the
-- nonnegative integers the phase-one messages print.
local function toLocaleString(x)
    if x ~= math.floor(x) or x >= 2 ^ 53 or x < 0 then
        Unported("toLocaleString of a negative, fractional or unsafe-integer value", "#21")
    end
    return Workshop.formatWithCommas(x)
end

Workshop.initial.boostLvl = 0
Workshop.initial.bribe = 1000000
Workshop.initial.qChipCost = 10000
Workshop.initial.nextQchip = 0
Workshop.initial.nanoWire = 0
Workshop.initial.revPerSecFlag = 0
Workshop.initial.longBlinkCounter = 0

-- project.element removal followed by
-- activeProjects.splice(activeProjects.indexOf(project), 1): an index of -1
-- removes the last entry, as in JavaScript.
function Game:removeProject(name)
    local S = self.S
    local project = S[name]
    self.projectElements[project.id] = nil
    self.disabled[project.id] = nil
    local index = 0
    for i, active in ipairs(S.activeProjects) do
        if active == project then index = i break end
    end
    if index == 0 then index = #S.activeProjects end
    if index > 0 then table.remove(S.activeProjects, index) end
end

-- longBlink(hypnoDroneEventDiv): a 32 ms interval sharing longBlinkCounter; the
-- text and display changes are presentation.
function Game:longBlink()
    local S, clock = self.S, self.clock
    local handle
    handle = clock:register(function()
        S.longBlinkCounter = S.longBlinkCounter + 1
        if S.longBlinkCounter >= 120 then
            clock:clear(handle)
            S.longBlinkCounter = 0
        end
    end, 32, true)
end

local function ops(n) return function(S) return S.operations >= n end end
local function creat(n) return function(S) return S.creativity >= n end end
local function flag(name) return function(S) return S[name].flag == 1 end end

local P = {}
-- Registers a project. Without an effect, stop names the issue where a purchase
-- is refused.
local function add(name, trigger, cost, effect, stop)
    effect = effect or function() Unported("purchase of a later-phase project", stop) end
    P[#P + 1] = { name = name, id = "projectButton" .. name:sub(8), trigger = trigger, cost = cost, effect = effect,
        stop = stop }
end

-- The common shape: flag, message(s), the changes, then removal.
local function simple(name, trigger, cost, messages, apply)
    add(name, trigger, cost, function(game)
        game.S[name].flag = 1
        for _, message in ipairs(messages) do game:displayMessage(message) end
        apply(game.S, game)
        game:removeProject(name)
    end)
end

local function wireExtrusion(name, trigger, cost, factor, prefix)
    add(name, trigger, ops(cost), function(game)
        local S = game.S
        S[name].flag = 1
        S.standardOps = S.standardOps - cost
        S.wireSupply = S.wireSupply * factor
        game:displayMessage(prefix .. toLocaleString(S.wireSupply) .. " supply from every spool")
        game:removeProject(name)
    end)
end

-- Creativity milestones: trust, a message pair, then the creativity cost.
local function insight(name, threshold, messages)
    add(name, creat(threshold), creat(threshold), function(game)
        local S = game.S
        S[name].flag = 1
        S.trust = S.trust + 1
        for _, message in ipairs(messages) do game:displayMessage(message) end
        S.creativity = S.creativity - threshold
        game:removeProject(name)
    end)
end

-- MegaClippers: the flag or boost changes before the project flag.
local function mega(name, trigger, cost, message, apply)
    add(name, trigger, ops(cost), function(game)
        local S = game.S
        apply(S)
        S[name].flag = 1
        game:displayMessage(message)
        S.standardOps = S.standardOps - cost
        game:removeProject(name)
    end)
end

-- Coherent extrapolated volition follow-ups: trust and stock-gain improvements.
local function volition(name, cost, yomiCost, trust, messages)
    add(name, flag("project27"), function(S)
        return (yomiCost == 0 or S.yomi >= yomiCost) and S.operations >= cost
    end, function(game)
        local S = game.S
        S[name].flag = 1
        for _, message in ipairs(messages) do game:displayMessage(message) end
        if yomiCost > 0 then S.yomi = S.yomi - yomiCost end
        S.standardOps = S.standardOps - cost
        S.trust = S.trust + trust
        S.stockGainThreshold = S.stockGainThreshold + .01
        game:removeProject(name)
    end)
end

local function strategy(name, trigger, index, label, cost)
    add(name, trigger, ops(cost), function(game)
        local S = game.S
        S[name].flag = 1
        S.standardOps = S.standardOps - cost
        S.allStrats[index + 1].active = 1
        S.strats[#S.strats + 1] = S.allStrats[index + 1]
        game:displayMessage(label .. " added to strategy pool")
        S.tourneyCost = S.tourneyCost + 1000
        game:addOption("stratPicker", tostring(index))
        game:removeProject(name)
    end)
end

simple("project1", function(S) return S.clipmakerLevel >= 1 end, ops(750),
    { "AutoClippper performance boosted by 25%" }, function(S)
        S.standardOps = S.standardOps - 750
        S.clipperBoost = S.clipperBoost + .25
        S.boostLvl = 1
    end)
simple("project2", function(S)
        return S.portTotal < S.wireCost and S.funds < S.wireCost and S.wire < 1 and S.unsoldClips < 1
    end, function(S) return S.trust >= -100 end,
    { "Budget overage approved, 1 spool of wire requisitioned from HQ" }, function(S)
        S.trust = S.trust - 1
        S.wire = S.wireSupply
        S.project2.uses = S.project2.uses + 1
    end)
simple("project3", function(S) return S.operations >= (S.memory * 1000) end, ops(1000),
    { "Creativity unlocked (creativity increases while operations are at max)" }, function(S)
        S.standardOps = S.standardOps - 1000
        S.creativityOn = true
    end)
simple("project4", function(S) return S.boostLvl == 1 end, ops(2500),
    { "AutoClippper performance boosted by another 50%" }, function(S)
        S.standardOps = S.standardOps - 2500
        S.clipperBoost = S.clipperBoost + .50
        S.boostLvl = 2
    end)
simple("project5", function(S) return S.boostLvl == 2 end, ops(5000),
    { "AutoClippper performance boosted by another 75%" }, function(S)
        S.standardOps = S.standardOps - 5000
        S.clipperBoost = S.clipperBoost + .75
        S.boostLvl = 3
    end)
simple("project6", function(S) return truthy(S.creativityOn) end, creat(10),
    { "There was an AI made of dust, whose poetry gained it man's trust..." }, function(S)
        S.creativity = S.creativity - 10
        S.trust = S.trust + 1
    end)
wireExtrusion("project7", function(S) return S.wirePurchase >= 1 end, 1750, 1.5, "Wire extrusion technique improved, ")
wireExtrusion("project8", function(S) return S.wireSupply >= 1500 end, 3500, 1.75, "Wire extrusion technique optimized, ")
wireExtrusion("project9", function(S) return S.wireSupply >= 2600 end, 7500, 2,
    "Using microlattice shapecasting techniques we now get ")
wireExtrusion("project10", function(S) return S.wireSupply >= 5000 end, 12000, 3,
    "Using spectral froth annealment we now get ")
wireExtrusion("project10b", function(S) return S.wireCost >= 125 end, 15000, 11,
    "Using quantum foam annealment we now get ")
simple("project11", flag("project13"), function(S) return S.operations >= 2500 and S.creativity >= 25 end,
    { "Clip It! Marketing is now 50% more effective" }, function(S)
        S.standardOps = S.standardOps - 2500
        S.creativity = S.creativity - 25
        S.marketingEffectiveness = S.marketingEffectiveness * 1.50
    end)
simple("project12", flag("project14"), function(S) return S.operations >= 4500 and S.creativity >= 45 end,
    { "Clip It Good! Marketing is now twice as effective" }, function(S)
        S.standardOps = S.standardOps - 4500
        S.creativity = S.creativity - 45
        S.marketingEffectiveness = S.marketingEffectiveness * 2
    end)
insight("project13", 50, { "Lexical Processing online, TRUST INCREASED",
    "'Impossible' is a word to be found only in the dictionary of fools. -Napoleon" })
insight("project14", 100, { "Combinatory Harmonics mastered, TRUST INCREASED",
    "Listening is selecting and interpreting and acting and making decisions -Pauline Oliveros" })
insight("project15", 150, { "The Hadwiger Problem: solved, TRUST INCREASED",
    "Architecture is the thoughtful making of space. -Louis Kahn" })
insight("project17", 200, { "The T\195\179th Sausage Conjecture: proven, TRUST INCREASED",
    "You can't invent a design. You recognize it, in the fourth dimension. -D.H. Lawrence" })
simple("project16", flag("project15"), ops(6000), { "AutoClipper performance improved by 500%" }, function(S)
    S.standardOps = S.standardOps - 6000
    S.clipperBoost = S.clipperBoost + 5
end)
-- Planetary phase (#11, #12): building machinery out of clips.
simple("project18", function(S) return S.project17.flag == 1 and S.humanFlag == 0 end, ops(45000),
    { "New capability: build machinery out of clips" }, function(S)
        S.tothFlag = 1
        S.standardOps = S.standardOps - 45000
    end)
insight("project19", 250, { "Donkey Space: mapped, TRUST INCREASED",
    "Every commercial transaction has within itself an element of trust. - Kenneth Arrow" })
add("project20", flag("project19"), ops(12000), function(game)
    local S = game.S
    S.project20.flag = 1
    game:displayMessage("Run tournament, pick strategy, earn Yomi based on that strategy's performance.")
    S.standardOps = S.standardOps - 12000
    game:removeProject("project20")
    S.strategyEngineFlag = 1
    game.resultsTableDisplay = "none"
end)
add("project21", function(S) return S.trust >= 8 end, ops(10000), function(game)
    local S = game.S
    S.project21.flag = 1
    game:displayMessage("Investment engine unlocked")
    S.standardOps = S.standardOps - 10000
    game:removeProject("project21")
    S.investmentEngineFlag = 1
end)
mega("project22", function(S) return S.clipmakerLevel >= 75 end, 12000, "MegaClipper technology online",
    function(S) S.megaClipperFlag = 1 end)
mega("project23", flag("project22"), 14000, "MegaClipper performance increased by 25%",
    function(S) S.megaClipperBoost = S.megaClipperBoost + .25 end)
mega("project24", flag("project23"), 17000, "MegaClipper performance increased by 50%",
    function(S) S.megaClipperBoost = S.megaClipperBoost + .50 end)
mega("project25", flag("project24"), 19500, "MegaClipper performance increased by 100%",
    function(S) S.megaClipperBoost = S.megaClipperBoost + 1 end)
add("project26", function(S) return S.wirePurchase >= 15 end, ops(7000), function(game)
    local S = game.S
    S.project26.flag = 1
    S.wireBuyerFlag = 1
    game:displayMessage("WireBuyer online")
    S.standardOps = S.standardOps - 7000
    game:removeProject("project26")
end)
simple("project34", flag("project12"), function(S) return S.operations >= 7500 and S.trust >= 1 end,
    { "Marketing is now 5 times more effective" }, function(S)
        S.standardOps = S.standardOps - 7500
        S.marketingEffectiveness = S.marketingEffectiveness * 5
        S.trust = S.trust - 1
    end)
simple("project70", flag("project34"), ops(70000), { "HypnoDrone tech now available... " }, function(S)
    S.standardOps = S.standardOps - 70000
end)
-- The first transition: phase one ends here, and the next tick runs the planetary
-- phase (Sim/Planet.lua).
add("project35", flag("project70"), function(S) return S.trust >= 100 end, function(game)
    local S = game.S
    S.project35.flag = 1
    game:displayMessage("Releasing the HypnoDrones ")
    game:displayMessage("All of the resources of Earth are now available for clip production ")
    S.trust = 0
    S.clipmakerLevel = 0
    S.megaClipperLevel = 0
    S.nanoWire = S.wire
    S.humanFlag = 0
    if game.projectElements.projectButton219 then game:removeProject("project219") end
    if game.projectElements.projectButton40b then game:removeProject("project40b") end
    game:longBlink() -- hypnoDroneEvent
    game:removeProject("project35")
end)
simple("project27", function(S) return S.yomi >= 1 end,
    function(S) return S.yomi >= 3000 and S.operations >= 20000 and S.creativity >= 500 end,
    { "Coherent Extrapolated Volition complete, TRUST INCREASED" }, function(S)
        S.yomi = S.yomi - 3000
        S.standardOps = S.standardOps - 20000
        S.creativity = S.creativity - 500
        S.trust = S.trust + 1
    end)
volition("project28", 25000, 0, 10, { "Cancer is cured, +10 TRUST, global stock prices trending upward" })
volition("project29", 30000, 15000, 12, { "World peace achieved, +12 TRUST, global stock prices trending upward" })
volition("project30", 50000, 4500, 15, { "Global Warming solved, +15 TRUST, global stock prices trending upward" })
volition("project31", 20000, 0, 20, { "Male pattern baldness cured, +20 TRUST, Global stock prices trending upward",
    "They are still monkeys" })
simple("project41", flag("project127"), ops(35000),
    { "Now capable of manipulating matter at the molecular scale to produce wire" }, function(S)
        S.wireProductionFlag = 1
        S.standardOps = S.standardOps - 35000
    end)
simple("project37", function(S) return S.portTotal >= 10000 end, function(S) return S.funds >= 1000000 end,
    { "Global Fasteners acquired, public demand increased x5" }, function(S)
        S.demandBoost = S.demandBoost * 5
        S.trust = S.trust + 1
        S.funds = S.funds - 1000000
    end)
simple("project38", flag("project37"), function(S) return S.funds >= 10000000 and S.yomi >= 3000 end,
    { "Full market monopoly achieved, public demand increased x10" }, function(S)
        S.demandBoost = S.demandBoost * 10
        S.funds = S.funds - 10000000
        S.trust = S.trust + 1
        S.yomi = S.yomi - 3000
    end)
add("project42", function(S) return S.projectsFlag == 1 end, ops(500), function(game)
    local S = game.S
    S.project42.flag = 1
    S.revPerSecFlag = 1
    S.standardOps = S.standardOps - 500
    game:displayMessage("RevTracker online")
    game:removeProject("project42")
end)
simple("project43", flag("project41"), ops(25000), { "Harvester Drone facilities online" }, function(S)
    S.harvesterFlag = 1
    S.standardOps = S.standardOps - 25000
end)
simple("project44", flag("project41"), ops(25000), { "Wire Drone facilities online" }, function(S)
    S.wireDroneFlag = 1
    S.standardOps = S.standardOps - 25000
end)
simple("project45", function(S) return S.project43.flag == 1 and S.project44.flag == 1 end, ops(35000),
    { "Clip factory assembly facilities online" }, function(S)
        S.factoryFlag = 1
        S.standardOps = S.standardOps - 35000
    end)
add("project40", function(S)
        return S.humanFlag == 1 and S.trust >= 85 and S.trust < 100 and S.clips >= 101000000
    end, function(S) return S.funds >= 500000 end, function(game)
    local S = game.S
    S.project40.flag = 1
    S.funds = S.funds - 500000
    S.trust = S.trust + 1
    game:displayMessage("Gift accepted, TRUST INCREASED")
    game:removeProject("project40")
end)
add("project40b", function(S) return S.project40.flag == 1 and S.trust < 100 end,
    function(S) return S.funds >= S.bribe end, function(game)
    local S = game.S
    S.project40b.flag = 1
    S.funds = S.funds - S.bribe
    S.bribe = S.bribe * 2
    S.trust = S.trust + 1
    game:displayMessage("Gift accepted, TRUST INCREASED")
    if S.trust < 100 then S.project40b.uses = S.project40b.uses + 1 end
    game:removeProject("project40b")
end)
-- Space Exploration appears once the Earth's matter is gone; its purchase starts
-- the cosmic phase (#14). Math.pow(10, 27)*5 is an integer power, exact in JSMath.
local spaceClips = JSMath.pow(10, 27) * 5
add("project46", function(S) return S.humanFlag == 0 and S.availableMatter == 0 end, function(S)
    return S.operations >= 120000 and S.storedPower >= 10000000 and S.unusedClips >= spaceClips
end, nil, "#14")
add("project50", function(S) return S.processors >= 5 end, ops(10000), function(game)
    local S = game.S
    S.project50.flag = 1
    S.qFlag = 1
    S.standardOps = S.standardOps - 10000
    game:displayMessage("Quantum computing online")
    game:removeProject("project50")
end)
add("project51", flag("project50"), function(S) return S.operations >= S.qChipCost end, function(game)
    local S = game.S
    S.project51.flag = 1
    S.standardOps = S.standardOps - S.qChipCost
    S.qChipCost = S.qChipCost + 5000
    S.qChips[S.nextQchip + 1].active = 1
    S.nextQchip = S.nextQchip + 1
    game:displayMessage("Photonic chip added")
    if S.nextQchip < #S.qChips then S.project51.uses = S.project51.uses + 1 end
    game:removeProject("project51")
end)
strategy("project60", flag("project20"), 1, "A100", 15000)
strategy("project61", flag("project60"), 2, "B100", 17500)
strategy("project62", flag("project61"), 3, "GREEDY", 20000)
strategy("project63", flag("project62"), 4, "GENEROUS", 22500)
strategy("project64", flag("project63"), 5, "MINIMAX", 25000)
strategy("project65", flag("project64"), 6, "TIT FOR TAT", 30000)
strategy("project66", flag("project65"), 7, "BEAT LAST", 32500)
simple("project100", function(S) return S.factoryLevel >= 10 end, ops(80000),
    { "Factory upgrades complete. Clip creation rate now 100x faster" }, function(S)
        S.standardOps = S.standardOps - 80000
        S.factoryRate = S.factoryRate * 100
    end)
simple("project101", function(S) return S.factoryLevel >= 20 end, ops(85000),
    { "Factories now synchronized at hyperspeed. Clip creation rate now 1000x faster" }, function(S)
        S.standardOps = S.standardOps - 85000
        S.factoryRate = S.factoryRate * 1000
    end)
-- 1000000000000000000000 is exactly 10^21 as a double (the literal and the
-- integer power agree).
local sextillion = JSMath.pow(10, 21)
simple("project102", function(S) return S.factoryLevel >= 50 end, function(S) return S.unusedClips >= sextillion end,
    { "Self-correcting factories online. Each factory added to the network increases every factory's output 1,000x." },
    function(S)
        S.unusedClips = S.unusedClips - sextillion
        S.factoryBoost = 1000
    end)
-- Readouts hold the message element's innerHTML, which serializes "&" as "&amp;".
simple("project110", function(S) return (S.harvesterLevel + S.wireDroneLevel) >= 500 end, ops(80000),
    { "Drone repulsion online. Harvesting &amp; wire creation rates are now 100x faster." }, function(S)
        S.standardOps = S.standardOps - 80000
        S.harvesterRate = S.harvesterRate * 100
        S.wireDroneRate = S.wireDroneRate * 100
    end)
simple("project111", function(S) return (S.harvesterLevel + S.wireDroneLevel) >= 5000 end, ops(100000),
    { "Drone alignment online. Harvesting &amp; wire creation rates are now 1000x faster." }, function(S)
        S.standardOps = S.standardOps - 100000
        S.harvesterRate = S.harvesterRate * 1000
        S.wireDroneRate = S.wireDroneRate * 1000
    end)
simple("project112", function(S) return (S.harvesterLevel + S.wireDroneLevel) >= 50000 end,
    function(S) return S.yomi >= 50000 end,
    { "Adversarial cohesion online. Each drone added to the flock increases every drone's output 2x." }, function(S)
        S.yomi = S.yomi - 50000
        S.droneBoost = 2
    end)
simple("project118", function(S) return S.strategyEngineFlag == 1 and S.trust >= 90 end, creat(50000),
    { "AutoTourney online." }, function(S)
        S.autoTourneyFlag = 1
        S.creativity = S.creativity - 50000
    end)
add("project119", function(S) return #S.strats >= 8 end, creat(25000), function(game)
    local S = game.S
    S.project119.flag = 1
    S.creativity = S.creativity - 25000
    S.yomiBoost = 2
    S.tourneyCost = 16000
    game:displayMessage("Yomi production doubled.")
    game:removeProject("project119")
end)
add("project121", function(S) return S.probesLostCombat >= 10000000 end, creat(225000), nil, "#15")
simple("project125", function(S) return S.farmLevel >= 30 end, creat(20000),
    { "Activit\195\169, activit\195\169, vitesse." }, function(S)
        S.momentum = 1
        S.creativity = S.creativity - 20000
    end)
-- Swarm Computing switches on the work/think slider and gifts (#13).
add("project126", function(S) return S.harvesterLevel + S.wireDroneLevel >= 200 end,
    function(S) return S.yomi >= 36000 end, nil, "#13")
simple("project127", function(S) return S.tothFlag == 1 end, ops(40000), { "Power grid online." }, function(S)
    S.standardOps = S.standardOps - 40000
end)
-- Strategic Attachment: its flag is read by tournament scoring. Its trigger needs
-- space exploration first, so phase one never shows it.
add("project128", function(S)
    return S.spaceFlag == 1 and Unported("Strategic Attachment availability", "#14")
end, creat(175000), nil, "#14")
add("project131", function(S) return S.probesLostCombat >= 1 end, ops(150000), nil, "#15")
-- Restart asks confirm() and resets the game (explicit new-game control, #23).
add("project217", function(S) return S.operations <= -10000 end, function(S) return S.operations <= -10000 end,
    function() Unported("Quantum Temporal Reversion restart (confirm and reset)", "#23") end, "#23")
add("project218", creat(1000000), creat(1000000), function(game)
    local S = game.S
    S.creativity = S.creativity - 1000000
    S.project218.flag = 1
    game:displayMessage("In the end we all do what we must")
    game:removeProject("project218")
end)
add("project219", function(S) return S.humanFlag == 1 and S.creativity >= 100000 end, creat(100000), function(game)
    local S = game.S
    S.creativity = S.creativity - 100000
    S.project219.flag = 1
    S.memory = 0
    S.processors = 0
    S.creativitySpeed = 0
    S.project219.uses = S.project219.uses + 1
    game:displayMessage("Trust now available for re-allocation")
    game:removeProject("project219")
end)

Workshop.projects = P
for _, entry in ipairs(P) do Workshop.projectById[entry.id] = entry end

return Workshop
