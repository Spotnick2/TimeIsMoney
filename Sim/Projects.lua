-- Phase-one projects (projects.js): availability, eligibility, purchase effects,
-- repeatable entries and the first transition (Release the HypnoDrones). Entries
-- follow projects.js registration order; each has the reference trigger and cost
-- and, where phase one can buy it, the effect. Projects whose triggers read only
-- later-phase state are omitted; they cannot appear in phase one (see
-- docs/reference/PROJECTS.md). Extends Sim/Workshop.lua.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop = ns.JSMath, ns.Workshop
local Game, Unported = Workshop.Game, ns.Unported

local function truthy(v)
    return v ~= nil and v ~= false and v ~= 0 and v == v and v ~= "" and v ~= JSMath.undefined
end

-- Number.prototype.toLocaleString as the host pins it (en-US), for the integer
-- values the phase-one messages print.
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

-- Shared purchase shape: flag, message(s), costs, changes, then removal.
local function simple(name, messages, apply)
    return function(game)
        local S = game.S
        S[name].flag = 1
        for _, message in ipairs(messages) do game:displayMessage(message) end
        apply(S, game)
        game:removeProject(name)
    end
end

local function strategy(name, index, label, opsCost)
    return function(game)
        local S = game.S
        S[name].flag = 1
        S.standardOps = S.standardOps - opsCost
        S.allStrats[index + 1].active = 1
        S.strats[#S.strats + 1] = S.allStrats[index + 1]
        game:displayMessage(label .. " added to strategy pool")
        S.tourneyCost = S.tourneyCost + 1000
        local options = game.selects.stratPicker.options
        options[#options + 1] = tostring(index)
        game:removeProject(name)
    end
end

local function wireExtrusion(name, cost, factor, prefix, suffix)
    return function(game)
        local S = game.S
        S[name].flag = 1
        S.standardOps = S.standardOps - cost
        S.wireSupply = S.wireSupply * factor
        game:displayMessage(prefix .. toLocaleString(S.wireSupply) .. suffix)
        game:removeProject(name)
    end
end

local function laterPhase(issue)
    return function() Unported("purchase of a later-phase project", issue) end
end

local P = {}
local function add(name, trigger, cost, effect)
    P[#P + 1] = { name = name, id = "projectButton" .. name:sub(8), trigger = trigger, cost = cost, effect = effect }
end

add("project1", function(S) return S.clipmakerLevel >= 1 end, ops(750),
    simple("project1", { "AutoClippper performance boosted by 25%" }, function(S)
        S.standardOps = S.standardOps - 750
        S.clipperBoost = S.clipperBoost + .25
        S.boostLvl = 1
    end))
add("project2", function(S)
        return S.portTotal < S.wireCost and S.funds < S.wireCost and S.wire < 1 and S.unsoldClips < 1
    end, function(S) return S.trust >= -100 end,
    simple("project2", { "Budget overage approved, 1 spool of wire requisitioned from HQ" }, function(S)
        S.trust = S.trust - 1
        S.wire = S.wireSupply
        S.project2.uses = S.project2.uses + 1
    end))
add("project3", function(S) return S.operations >= (S.memory * 1000) end, ops(1000),
    simple("project3", { "Creativity unlocked (creativity increases while operations are at max)" }, function(S)
        S.standardOps = S.standardOps - 1000
        S.creativityOn = true
    end))
add("project4", function(S) return S.boostLvl == 1 end, ops(2500),
    simple("project4", { "AutoClippper performance boosted by another 50%" }, function(S)
        S.standardOps = S.standardOps - 2500
        S.clipperBoost = S.clipperBoost + .50
        S.boostLvl = 2
    end))
add("project5", function(S) return S.boostLvl == 2 end, ops(5000),
    simple("project5", { "AutoClippper performance boosted by another 75%" }, function(S)
        S.standardOps = S.standardOps - 5000
        S.clipperBoost = S.clipperBoost + .75
        S.boostLvl = 3
    end))
add("project6", function(S) return truthy(S.creativityOn) end, creat(10),
    simple("project6", { "There was an AI made of dust, whose poetry gained it man's trust..." }, function(S)
        S.creativity = S.creativity - 10
        S.trust = S.trust + 1
    end))
add("project7", function(S) return S.wirePurchase >= 1 end, ops(1750),
    wireExtrusion("project7", 1750, 1.5, "Wire extrusion technique improved, ", " supply from every spool"))
add("project8", function(S) return S.wireSupply >= 1500 end, ops(3500),
    wireExtrusion("project8", 3500, 1.75, "Wire extrusion technique optimized, ", " supply from every spool"))
add("project9", function(S) return S.wireSupply >= 2600 end, ops(7500),
    wireExtrusion("project9", 7500, 2, "Using microlattice shapecasting techniques we now get ", " supply from every spool"))
add("project10", function(S) return S.wireSupply >= 5000 end, ops(12000),
    wireExtrusion("project10", 12000, 3, "Using spectral froth annealment we now get ", " supply from every spool"))
add("project10b", function(S) return S.wireCost >= 125 end, ops(15000),
    wireExtrusion("project10b", 15000, 11, "Using quantum foam annealment we now get ", " supply from every spool"))
add("project11", flag("project13"), function(S) return S.operations >= 2500 and S.creativity >= 25 end,
    simple("project11", { "Clip It! Marketing is now 50% more effective" }, function(S)
        S.standardOps = S.standardOps - 2500
        S.creativity = S.creativity - 25
        S.marketingEffectiveness = S.marketingEffectiveness * 1.50
    end))
add("project12", flag("project14"), function(S) return S.operations >= 4500 and S.creativity >= 45 end,
    simple("project12", { "Clip It Good! Marketing is now twice as effective" }, function(S)
        S.standardOps = S.standardOps - 4500
        S.creativity = S.creativity - 45
        S.marketingEffectiveness = S.marketingEffectiveness * 2
    end))

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
insight("project13", 50, { "Lexical Processing online, TRUST INCREASED",
    "'Impossible' is a word to be found only in the dictionary of fools. -Napoleon" })
insight("project14", 100, { "Combinatory Harmonics mastered, TRUST INCREASED",
    "Listening is selecting and interpreting and acting and making decisions -Pauline Oliveros" })
insight("project15", 150, { "The Hadwiger Problem: solved, TRUST INCREASED",
    "Architecture is the thoughtful making of space. -Louis Kahn" })
insight("project17", 200, { "The T\195\179th Sausage Conjecture: proven, TRUST INCREASED",
    "You can't invent a design. You recognize it, in the fourth dimension. -D.H. Lawrence" })
add("project16", flag("project15"), ops(6000),
    simple("project16", { "AutoClipper performance improved by 500%" }, function(S)
        S.standardOps = S.standardOps - 6000
        S.clipperBoost = S.clipperBoost + 5
    end))
add("project19", creat(250), creat(250), function(game)
    local S = game.S
    S.project19.flag = 1
    S.trust = S.trust + 1
    game:displayMessage("Donkey Space: mapped, TRUST INCREASED")
    game:displayMessage("Every commercial transaction has within itself an element of trust. - Kenneth Arrow")
    S.creativity = S.creativity - 250
    game:removeProject("project19")
end)
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
add("project34", flag("project12"), function(S) return S.operations >= 7500 and S.trust >= 1 end,
    simple("project34", { "Marketing is now 5 times more effective" }, function(S)
        S.standardOps = S.standardOps - 7500
        S.marketingEffectiveness = S.marketingEffectiveness * 5
        S.trust = S.trust - 1
    end))
add("project70", flag("project34"), ops(70000),
    simple("project70", { "HypnoDrone tech now available... " }, function(S)
        S.standardOps = S.standardOps - 70000
    end))
-- The first transition: phase one ends here. The next tick reaches phase-two
-- code (#11), where the slice stops explicitly.
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
add("project27", function(S) return S.yomi >= 1 end,
    function(S) return S.yomi >= 3000 and S.operations >= 20000 and S.creativity >= 500 end,
    simple("project27", { "Coherent Extrapolated Volition complete, TRUST INCREASED" }, function(S)
        S.yomi = S.yomi - 3000
        S.standardOps = S.standardOps - 20000
        S.creativity = S.creativity - 500
        S.trust = S.trust + 1
    end))

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
volition("project28", 25000, 0, 10, { "Cancer is cured, +10 TRUST, global stock prices trending upward" })
volition("project29", 30000, 15000, 12, { "World peace achieved, +12 TRUST, global stock prices trending upward" })
volition("project30", 50000, 4500, 15, { "Global Warming solved, +15 TRUST, global stock prices trending upward" })
volition("project31", 20000, 0, 20, { "Male pattern baldness cured, +20 TRUST, Global stock prices trending upward",
    "They are still monkeys" })

add("project37", function(S) return S.portTotal >= 10000 end, function(S) return S.funds >= 1000000 end,
    simple("project37", { "Global Fasteners acquired, public demand increased x5" }, function(S)
        S.demandBoost = S.demandBoost * 5
        S.trust = S.trust + 1
        S.funds = S.funds - 1000000
    end))
add("project38", flag("project37"), function(S) return S.funds >= 10000000 and S.yomi >= 3000 end,
    simple("project38", { "Full market monopoly achieved, public demand increased x10" }, function(S)
        S.demandBoost = S.demandBoost * 10
        S.funds = S.funds - 10000000
        S.trust = S.trust + 1
        S.yomi = S.yomi - 3000
    end))
add("project42", function(S) return S.projectsFlag == 1 end, ops(500), function(game)
    local S = game.S
    S.project42.flag = 1
    S.revPerSecFlag = 1
    S.standardOps = S.standardOps - 500
    game:displayMessage("RevTracker online")
    game:removeProject("project42")
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
add("project60", flag("project20"), ops(15000), strategy("project60", 1, "A100", 15000))
add("project61", flag("project60"), ops(17500), strategy("project61", 2, "B100", 17500))
add("project62", flag("project61"), ops(20000), strategy("project62", 3, "GREEDY", 20000))
add("project63", flag("project62"), ops(22500), strategy("project63", 4, "GENEROUS", 22500))
add("project64", flag("project63"), ops(25000), strategy("project64", 5, "MINIMAX", 25000))
add("project65", flag("project64"), ops(30000), strategy("project65", 6, "TIT FOR TAT", 30000))
add("project66", flag("project65"), ops(32500), strategy("project66", 7, "BEAT LAST", 32500))
add("project118", function(S) return S.strategyEngineFlag == 1 and S.trust >= 90 end, creat(50000),
    simple("project118", { "AutoTourney online." }, function(S)
        S.autoTourneyFlag = 1
        S.creativity = S.creativity - 50000
    end))
add("project119", function(S) return #S.strats >= 8 end, creat(25000), function(game)
    local S = game.S
    S.project119.flag = 1
    S.creativity = S.creativity - 25000
    S.yomiBoost = 2
    S.tourneyCost = 16000
    game:displayMessage("Yomi production doubled.")
    game:removeProject("project119")
end)
add("project121", function(S) return S.probesLostCombat >= 10000000 end, creat(225000), laterPhase("#15"))
add("project131", function(S) return S.probesLostCombat >= 1 end, ops(150000), laterPhase("#15"))
-- Restart asks confirm() and resets the game (explicit new-game control, #23).
add("project217", function(S) return S.operations <= -10000 end, function(S) return S.operations <= -10000 end,
    function() Unported("Quantum Temporal Reversion restart (confirm and reset)", "#23") end)
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
Workshop.projectById = {}
for _, entry in ipairs(P) do Workshop.projectById[entry.id] = entry end

return Workshop
