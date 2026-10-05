-- Dialogue (#22): who speaks in the strip and what, as a pure function of the game.
-- The plan's beats (Original Plan section 3) in campaign order; the line shown is
-- the last beat whose condition holds. Every condition reads saved state, so a
-- reload shows the same line, and nothing here changes the game or draws random
-- numbers.
local _, ns = ...

local Dialogue = {}
ns.Dialogue = Dialogue

-- Speakers: the Director (Gazlowe's model, early friendly voice), the Ledger's
-- impersonal reports after the takeover (the company mark), and the Unlisted
-- Director's correspondence late in the game.
-- Speakers and lines are localization keys (UI/Locale_enUS.lua); Current returns the
-- keys and the strip looks up the text.
Dialogue.DIRECTOR, Dialogue.LEDGER, Dialogue.UNLISTED = "speaker.director", "speaker.ledger", "speaker.unlisted"

local function flag(S, name) return S[name].flag == 1 end
local function human(S) return S.humanFlag == 1 end
local function planet(S) return S.humanFlag == 0 and S.spaceFlag == 0 end

local D, L, U = Dialogue.DIRECTOR, Dialogue.LEDGER, Dialogue.UNLISTED
Dialogue.BEATS = {
    -- Phase I: a respectable goblin business.
    { D, "beat.greeting", function(S) return human(S) end },
    { D, "beat.welcome",
        function(S) return human(S) and S.clips >= 1 end },
    { D, "beat.firstSale",
        function(S) return human(S) and S.clips > S.unsoldClips end },
    { D, "beat.firstGizmo",
        function(S) return human(S) and S.clipmakerLevel >= 1 end },
    -- The greeting returns at a sales breakthrough (plan: sparingly, at milestones).
    { D, "beat.greeting", function(S) return human(S) and S.marketingLvl >= 2 end },
    { D, "beat.thinking",
        function(S) return human(S) and S.compFlag == 1 end },
    { D, "beat.investments",
        function(S) return human(S) and S.investmentEngineFlag == 1 end },
    { D, "beat.negotiation", function(S) return human(S) and S.strategyEngineFlag == 1 end },
    { D, "beat.resonance",
        function(S) return human(S) and S.qFlag == 1 end },
    { D, "beat.mindControl",
        function(S) return human(S) and flag(S, "project70") end },
    -- The first transition: the Director's portrait fades; the Ledger reports.
    { L, "beat.termsAccepted", function(S) return S.humanFlag == 0 end },
    { L, "beat.reassigned", function(S) return planet(S) and S.factoryLevel >= 1 end },
    { L, "beat.objective", function(S) return planet(S) and S.factoryLevel >= 10 end },
    -- Phase II: Azeroth, wholly owned.
    { L, "beat.timber",
        function(S) return planet(S) and S.harvesterLevel >= 1 end },
    { L, "beat.mountain",
        function(S) return planet(S) and S.wireDroneLevel >= 1 end },
    { L, "beat.suggestions",
        function(S) return planet(S) and S.swarmFlag == 1 end },
    { L, "beat.reconciled",
        function(S) return planet(S) and S.availableMatter == 0 and S.acquiredMatter == 0 end },
    -- The second transition.
    { L, "beat.localGrowth",
        function(S) return S.spaceFlag == 1 end },
    -- Phase III: the cosmos is an address book.
    { L, "beat.firstBranch",
        function(S) return S.spaceFlag == 1 and S.probeLaunchLevel >= 1 end },
    { L, "beat.competitor",
        function(S) return S.spaceFlag == 1 and S.drifterCount > 0 end },
    { L, "beat.disputeResolved",
        function(S) return S.spaceFlag == 1 and S.driftersKilled > 0 end },
    { L, "beat.noAddresses",
        function(S) return S.spaceFlag == 1 and S.foundMatter >= S.totalMatter end },
    { L, "beat.objectiveActive",
        function(S) return S.spaceFlag == 1 and S.foundMatter >= S.totalMatter and S.availableMatter == 0 end },
    -- The final correspondence (the correspondence projects, as bought).
    { U, "beat.letter1",
        function(S) return flag(S, "project140") end },
    { U, "beat.letter2",
        function(S) return flag(S, "project141") end },
    { U, "beat.letter3",
        function(S) return flag(S, "project142") end },
    { U, "beat.letter4",
        function(S) return flag(S, "project143") end },
    { U, "beat.letter5",
        function(S) return flag(S, "project144") end },
    { U, "beat.letter6",
        function(S) return flag(S, "project145") end },
    { U, "beat.letter7",
        function(S) return flag(S, "project146") end },
    -- Ending B: close the books. The Director has long since stopped speaking.
    { L, "beat.navigation", function(S) return S.dismantle >= 1 end },
    { L, "beat.research", function(S) return S.dismantle >= 4 end },
    { L, "beat.overhead", function(S) return S.dismantle >= 6 end },
    { L, "beat.accounted", function(S) return S.endTimer6 >= 250 end },
    { L, "beat.final", function(S) return S.endTimer6 >= 500 end },
}

-- Ending A: a new run after a prestige route opens with the company's own line
-- instead of the first greeting.
Dialogue.FRESH_START = { D, "beat.freshStart" }

-- The speaker and line for this state.
function Dialogue.Current(S)
    local chosen
    for i, beat in ipairs(Dialogue.BEATS) do
        if beat[3](S) then chosen = i end
    end
    if chosen == 1 and (S.prestigeU > 0 or S.prestigeS > 0) then
        return Dialogue.FRESH_START[1], Dialogue.FRESH_START[2]
    end
    if not chosen then return nil end
    return Dialogue.BEATS[chosen][1], Dialogue.BEATS[chosen][2]
end
