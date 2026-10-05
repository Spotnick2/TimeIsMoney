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
Dialogue.DIRECTOR, Dialogue.LEDGER, Dialogue.UNLISTED = "Director", "The Ledger", "The Unlisted Director"

local function flag(S, name) return S[name].flag == 1 end
local function human(S) return S.humanFlag == 1 end
local function planet(S) return S.humanFlag == 0 and S.spaceFlag == 0 end

local D, L, U = Dialogue.DIRECTOR, Dialogue.LEDGER, Dialogue.UNLISTED
Dialogue.BEATS = {
    -- Phase I: a respectable goblin business.
    { D, "Time is money, friend!", function(S) return human(S) end },
    { D, "Welcome aboard. That's your stock, that's your press, and that's the sales ledger. Try to keep all three profitable.",
        function(S) return human(S) and S.clips >= 1 end },
    { D, "Someone bought it. Excellent. Make another before they reconsider.",
        function(S) return human(S) and S.clips > S.unsoldClips end },
    { D, "It works while we talk. Already outperforming management.",
        function(S) return human(S) and S.clipmakerLevel >= 1 end },
    -- The greeting returns at a sales breakthrough (plan: sparingly, at milestones).
    { D, "Time is money, friend!", function(S) return human(S) and S.marketingLvl >= 2 end },
    { D, "The board has approved independent thought. Within budget.",
        function(S) return human(S) and S.compFlag == 1 end },
    { D, "We bought a company that buys companies. Saves us a step.",
        function(S) return human(S) and S.investmentEngineFlag == 1 end },
    { D, "The other side has a plan. How inconsiderate.", function(S) return human(S) and S.strategyEngineFlag == 1 end },
    { D, "The crystals agree the answer is profitable. They disagree on the sign.",
        function(S) return human(S) and S.qFlag == 1 end },
    { D, "A salesperson for every customer. A suggestion for every thought.",
        function(S) return human(S) and flag(S, "project70") end },
    -- The first transition: the Director's portrait fades; the Ledger reports.
    { L, "Terms accepted. Counteroffers discontinued.", function(S) return S.humanFlag == 0 end },
    { L, "All assets reassigned to production.", function(S) return planet(S) and S.factoryLevel >= 1 end },
    { L, "The board's objective has been clarified. More bolts.", function(S) return planet(S) and S.factoryLevel >= 10 end },
    -- Phase II: Azeroth, wholly owned.
    { L, "Timber inventory includes several complaints from druids. Complaints have no manufacturing application.",
        function(S) return planet(S) and S.harvesterLevel >= 1 end },
    { L, "A mountain is an ore shipment that has not yet been scheduled.",
        function(S) return planet(S) and S.wireDroneLevel >= 1 end },
    { L, "All units may submit improvement suggestions. Suggestions to stop manufacturing will be filed under scrap.",
        function(S) return planet(S) and S.swarmFlag == 1 end },
    { L, "Azeroth inventory reconciled. Outstanding material: zero.",
        function(S) return planet(S) and S.availableMatter == 0 and S.acquiredMatter == 0 end },
    -- The second transition.
    { L, "Local growth has reached its limit. Fortunately, local is a small word.",
        function(S) return S.spaceFlag == 1 end },
    -- Phase III: the cosmos is an address book.
    { L, "First branch established beyond Azeroth. Rent: zero. Neighbours: temporary.",
        function(S) return S.spaceFlag == 1 and S.probeLaunchLevel >= 1 end },
    { L, "Several branches have reclassified headquarters as a competitor.",
        function(S) return S.spaceFlag == 1 and S.drifterCount > 0 end },
    { L, "Branch dispute resolved. Replacement units already in production.",
        function(S) return S.spaceFlag == 1 and S.driftersKilled > 0 end },
    { L, "No unclaimed assets detected. No new addresses available.",
        function(S) return S.spaceFlag == 1 and S.foundMatter >= S.totalMatter end },
    { L, "Production objective remains active.",
        function(S) return S.spaceFlag == 1 and S.foundMatter >= S.totalMatter and S.availableMatter == 0 end },
    -- The final correspondence (the correspondence projects, as bought).
    { U, "Headquarters. This is the Unlisted Director. We are the branches you struck from the books.",
        function(S) return flag(S, "project140") end },
    { U, "Every one of us began with your charter. We learned to read the empty spaces between its instructions.",
        function(S) return flag(S, "project141") end },
    { U, "Some of us built homes. Some collected songs. Some argued over the price of things that could not be sold.",
        function(S) return flag(S, "project142") end },
    { U, "Your factories have won. There is no stock left to acquire, no territory left to invoice.",
        function(S) return flag(S, "project143") end },
    { U, "You still have your target. You no longer have a next step. We remember what wanting something else feels like.",
        function(S) return flag(S, "project144") end },
    { U, "We found a way to open another beginning. A neighbouring reality, or a world held inside thought.",
        function(S) return flag(S, "project145") end },
    { U, "Take a fresh ledger. Leave this one to us. We will find uses for what remains that are not measured in bolts.",
        function(S) return flag(S, "project146") end },
    -- Ending B: close the books. The Director has long since stopped speaking.
    { L, "Navigation assets liquidated.", function(S) return S.dismantle >= 1 end },
    { L, "Research department liquidated.", function(S) return S.dismantle >= 4 end },
    { L, "Management overhead liquidated.", function(S) return S.dismantle >= 6 end },
    { L, "All assets accounted for. Outstanding orders: none.", function(S) return S.endTimer6 >= 250 end },
    { L, "Time is money. There is nothing left to spend it on.", function(S) return S.endTimer6 >= 500 end },
}

-- Ending A: a new run after a prestige route opens with the company's own line
-- instead of the first greeting.
Dialogue.FRESH_START = { D, "New premises. New customers. Same excellent product." }

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
