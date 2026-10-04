-- Strategic modeling (main.js): tournaments of the purchased strategies on a
-- random payoff grid, 50 ms round timers, scoring, placing and Yomi, the strategy
-- picker and automatic tournaments. Extends Sim/Workshop.lua; strategy objects keep
-- their reference fields (name, active, currentScore, currentPos) and pickMove is
-- dispatched by name. Strategy purchases are project effects (Sim/Projects.lua).
local _, ns = ...
ns = ns or {}

local JSMath, Workshop = ns.JSMath, ns.Workshop
local Game, Unported = Workshop.Game, ns.Unported
local floor, ceil = math.floor, math.ceil
local toNumber, toString = JSMath.toNumber, JSMath.toString

local initial = {
    tourneyCost = 1000, tourneyLvl = 1, stratCounter = 0, roundNum = 0, hMove = 1, vMove = 1,
    hMovePrev = 1, vMovePrev = 1, aa = 0, ab = 0, ba = 0, bb = 0, rounds = 0, currentRound = 0,
    rCounter = 0, tourneyInProg = 0, winnerPtr = 0, placeScore = 0, showScore = 0, high = 0,
    pick = 10, yomi = 0, yomiBoost = 1, resultsTimer = 0, strategyEngineFlag = 0,
    -- Implicit globals that tournaments create (pickStrats, TIT FOR TAT, and the
    -- scoring loops' n; i is shared with combat.js and calculateRev).
    h = JSMath.undefined, v = JSMath.undefined, w = JSMath.undefined, n = JSMath.undefined,
}
for key, value in pairs(initial) do Workshop.initial[key] = value end
for _, key in ipairs({ "choiceANames", "choiceBNames", "allStrats", "strats", "results" }) do
    Workshop.arrays[key] = true
end
for _, id in ipairs({ "btnNewTournament", "btnRunTournament", "btnToggleAutoTourney" }) do
    Workshop.buttons[#Workshop.buttons + 1] = id
end

local STRATEGIES = { "RANDOM", "A100", "B100", "GREEDY", "GENEROUS", "MINIMAX", "TIT FOR TAT", "BEAT LAST" }

Workshop.setups[#Workshop.setups + 1] = function(game, S)
    S.choiceANames = { "cooperate", "swerve", "macro", "fight", "bet", "raise_price", "opera", "go", "heads",
        "particle", "discrete", "peace", "search", "lead", "accept", "accept", "attack" }
    S.choiceBNames = { "defect", "straight", "micro", "back_down", "fold", "lower_price", "football", "stay",
        "tails", "wave", "continuous", "war", "evaluate", "follow", "reject", "deny", "decay" }
    S.payoffGrid = { valueAA = 0, valueAB = 0, valueBA = 0, valueBB = 0 }
    S.allStrats = {}
    for i, name in ipairs(STRATEGIES) do
        S.allStrats[i] = { name = name, active = i == 1 and 1 or 0, currentScore = 0, currentPos = 1 }
    end
    S.strats = { S.allStrats[1] }
    S.results = {}
    S.hStrat, S.vStrat = S.strats[1], S.strats[1]
    game.disabled.btnRunTournament = true -- main.js load
    game.resultsTableDisplay = ""
end

local function findBiggestPayoff(S)
    local aa, ab, ba, bb = S.aa, S.ab, S.ba, S.bb
    if aa >= ab and aa >= ba and aa >= bb then return 1 end
    if ab >= aa and ab >= ba and ab >= bb then return 2 end
    if ba >= aa and ba >= ab and ba >= bb then return 3 end
    return 4
end

local function whatBeatsLast(S, myPos)
    local oppsPos = myPos == 1 and 2 or 1
    if oppsPos == 1 and S.hMovePrev == 1 then
        return S.aa > S.ba and 1 or 2
    elseif oppsPos == 1 and S.hMovePrev == 2 then
        return S.ab > S.bb and 1 or 2
    elseif oppsPos == 2 and S.vMovePrev == 1 then
        return S.aa > S.ba and 1 or 2
    end
    return S.ab > S.bb and 1 or 2
end

local pickMoves = {
    ["RANDOM"] = function(game) return game.draw("main.js:1737:22") < .5 and 1 or 2 end,
    ["A100"] = function() return 1 end,
    ["B100"] = function() return 2 end,
    ["GREEDY"] = function(game) return findBiggestPayoff(game.S) < 3 and 1 or 2 end,
    ["GENEROUS"] = function(game)
        local x = findBiggestPayoff(game.S)
        return (x == 1 or x == 3) and 1 or 2
    end,
    ["MINIMAX"] = function(game)
        local x = findBiggestPayoff(game.S)
        return (x == 1 or x == 3) and 2 or 1
    end,
    ["TIT FOR TAT"] = function(game, strat)
        local S = game.S
        if strat.currentPos == 1 then S.w = S.vMovePrev else S.w = S.hMovePrev end
        return S.w
    end,
    ["BEAT LAST"] = function(game, strat) return whatBeatsLast(game.S, strat.currentPos) end,
}

local function pickMove(game, strat) return pickMoves[strat.name](game, strat) end

function Game:pickStrats(roundNum)
    local S = self.S
    local count = #S.strats
    if roundNum < count then
        S.h = 0
        S.v = roundNum
    else
        S.stratCounter = S.stratCounter + 1
        if S.stratCounter >= count then S.stratCounter = S.stratCounter - count end
        S.h = floor(roundNum / count)
        S.v = S.stratCounter
    end
    S.vStrat = S.strats[S.v + 1]
    S.hStrat = S.strats[S.h + 1]
    S.strats[S.h + 1].currentPos = 1
    S.strats[S.v + 1].currentPos = 2
end

function Game:generateGrid()
    local S = self.S
    local grid = S.payoffGrid
    grid.valueAA = ceil(self.draw("main.js:1944:41") * 10)
    grid.valueAB = ceil(self.draw("main.js:1945:41") * 10)
    grid.valueBA = ceil(self.draw("main.js:1946:41") * 10)
    grid.valueBB = ceil(self.draw("main.js:1947:41") * 10)
    S.aa, S.ab, S.ba, S.bb = grid.valueAA, grid.valueAB, grid.valueBA, grid.valueBB
    self.draw("main.js:1954:29") -- picks the choice labels (presentation)
end

function Game:toggleAutoTourney()
    local S = self.S
    if S.autoTourneyStatus == 1 then S.autoTourneyStatus = 0 else S.autoTourneyStatus = 1 end
end

function Game:newTourney()
    local S = self.S
    S.resultsFlag = 0
    self.resultsTableDisplay = "none"
    S.high = 0
    S.tourneyInProg = 1
    S.currentRound = 0
    S.rounds = #S.strats * #S.strats
    for _, strat in ipairs(S.strats) do strat.currentScore = 0 end
    S.i = #S.strats
    S.stratCounter = 0
    S.standardOps = S.standardOps - S.tourneyCost
    S.tourneyLvl = S.tourneyLvl + 1
    self:generateGrid()
    self.disabled.btnRunTournament = false
end

function Game:calcPayoff(hm, vm)
    local S = self.S
    local grid, hs, vs = S.payoffGrid, S.strats[S.h + 1], S.strats[S.v + 1]
    if hm == 1 and vm == 1 then
        hs.currentScore = hs.currentScore + grid.valueAA
        vs.currentScore = vs.currentScore + grid.valueAA
    elseif hm == 1 and vm == 2 then
        hs.currentScore = hs.currentScore + grid.valueAB
        vs.currentScore = vs.currentScore + grid.valueBA
    elseif hm == 2 and vm == 1 then
        hs.currentScore = hs.currentScore + grid.valueBA
        vs.currentScore = vs.currentScore + grid.valueAB
    elseif hm == 2 and vm == 2 then
        hs.currentScore = hs.currentScore + grid.valueBB
        vs.currentScore = vs.currentScore + grid.valueBB
    end
end

-- round(roundNum): ten moves, each followed by clearGrid and the next move after
-- two chained 50 ms timeouts; then the next round. The two timeouts are named
-- timer kinds (tourneyClear, tourneyLoop) so a saved tournament continues (#19).
function Game:roundLoop()
    local S = self.S
    if S.rCounter < 10 then
        S.rCounter = S.rCounter + 1
        S.hMovePrev = S.hMove
        S.vMovePrev = S.vMove
        S.hMove = pickMove(self, S.hStrat)
        S.vMove = pickMove(self, S.vStrat)
        self:calcPayoff(S.hMove, S.vMove)
        self:schedule("tourneyClear", 50, false)
    else
        S.currentRound = S.currentRound + 1
        self:runTourney()
    end
end
Workshop.timers.tourneyClear = function(game) game:schedule("tourneyLoop", 50, false) end
Workshop.timers.tourneyLoop = function(game) game:roundLoop() end

function Game:round(roundNum)
    self.S.rCounter = 0
    self:pickStrats(roundNum)
    self:roundLoop()
end

function Game:pickWinner()
    local S = self.S
    S.results = {}
    local temp = {}
    for i, strat in ipairs(S.strats) do temp[i] = strat end
    for n = 1, #S.strats do
        S.n = n - 1
        local tempHigh, tempWinnerPtr = 0, 1
        for i, strat in ipairs(temp) do
            if strat.currentScore > tempHigh then
                tempWinnerPtr = i
                tempHigh = strat.currentScore
            end
        end
        S.i = #temp
        S.results[#S.results + 1] = temp[tempWinnerPtr]
        table.remove(temp, tempWinnerPtr)
    end
    S.n = #S.strats
    for i, strat in ipairs(S.strats) do
        if strat.currentScore > S.high then
            S.winnerPtr = i - 1
            S.high = strat.currentScore
        end
    end
    S.i = #S.strats
end

function Game:calculatePlaceScore()
    local S = self.S
    S.placeScore = 0
    S.i = math.max(1, #S.results)
    for i = 2, #S.results do
        if S.results[i].currentScore < S.results[i - 1].currentScore then
            S.placeScore = S.results[i].currentScore
            S.i = i - 1
            break
        end
    end
end

function Game:calculateShowScore()
    local S = self.S
    S.showScore = 0
    S.i = math.max(1, #S.results)
    for i = 2, #S.results do
        if S.results[i].currentScore < S.placeScore then
            S.showScore = S.results[i].currentScore
            S.i = i - 1
            break
        end
    end
end

-- strats[pick]: a property key, so only a number or a canonical integer string
-- such as "0" names an element ("" and "00" do not). The reference then throws
-- reading .name of undefined; the port stops there explicitly.
local function picked(S)
    local pick, strat = S.pick, nil
    if type(pick) == "number" then
        strat = pick == floor(pick) and S.strats[pick + 1] or nil
    elseif type(pick) == "string" and (pick == "0" or pick:match("^[1-9]%d*$")) then
        strat = S.strats[tonumber(pick) + 1]
    end
    if not strat then Unported("reference TypeError: strats[pick] is undefined", "#20") end
    return strat
end

function Game:calculateStratsBeat()
    local S = self.S
    local name = picked(S).name
    for i, strat in ipairs(S.results) do
        if strat.name == name then
            S.i = i - 1
            return #S.results - (i - 1)
        end
    end
    S.i = #S.results
    return JSMath.undefined
end

function Game:declareWinner()
    local S = self.S
    if toNumber(S.pick) < 10 then
        local strat = picked(S)
        local bB, w = 0, "strats"
        local beatBoost = JSMath.num(self:calculateStratsBeat()) - 1
        if beatBoost == 1 then w = "strat" end
        if beatBoost == 0 then
            bB = 0
            beatBoost = 1
        else
            bB = beatBoost
        end
        S.yomi = S.yomi + strat.currentScore * S.yomiBoost * beatBoost
        if S.milestoneFlag < 15 then
            self:displayMessage(strat.name .. " scored " .. toString(strat.currentScore) .. " and beat " ..
                toString(bB) .. " " .. w .. ". Yomi increased by " ..
                toString(strat.currentScore * S.yomiBoost * beatBoost))
        end
        -- Strategic Attachment (#14): placing bonuses for the picked strategy.
        if S.project128.flag == 1 and S.strats[S.winnerPtr + 1].currentScore == strat.currentScore then
            S.yomi = S.yomi + 50000
            if S.milestoneFlag < 15 then
                self:displayMessage("Selected strategy won the tournament (or tied for first). +50,000 yomi")
            end
        elseif S.project128.flag == 1 and S.placeScore == strat.currentScore then
            S.yomi = S.yomi + 30000
            if S.milestoneFlag < 15 then
                self:displayMessage("Selected strategy finished in (or tied for) second place. +30,000 yomi")
            end
        elseif S.project128.flag == 1 and S.showScore == strat.currentScore then
            S.yomi = S.yomi + 20000
            if S.milestoneFlag < 15 then
                self:displayMessage("Selected strategy finished in (or tied for) third place. +20,000 yomi")
            end
        end
        -- populateTourneyReport (presentation, but its loop leaves i):
        S.i = #S.results
        -- displayTourneyReport:
        S.resultsFlag = 1
        self.resultsTableDisplay = ""
    end
end

function Game:runTourney()
    local S = self.S
    self.disabled.btnRunTournament = true
    if S.currentRound < S.rounds then
        self:round(S.currentRound)
    else
        S.tourneyInProg = 0
        self:pickWinner()
        self:calculatePlaceScore()
        self:calculateShowScore()
        self:declareWinner()
    end
end

-- buttonUpdate's automatic tournament, while the results table is shown.
function Game:autoTourney()
    local S = self.S
    if S.resultsFlag == 1 and S.autoTourneyFlag == 1 and S.autoTourneyStatus == 1 and self.resultsTableDisplay == "" then
        S.resultsTimer = S.resultsTimer + 1
        if S.resultsTimer >= 300 and S.operations >= S.tourneyCost then
            self:newTourney()
            self:runTourney()
            S.resultsTimer = 0
        end
    end
end

local clicks = Workshop.clicks
clicks.btnNewTournament = Game.newTourney
clicks.btnRunTournament = Game.runTourney
clicks.btnToggleAutoTourney = Game.toggleAutoTourney

return Workshop
