-- The company's reports (#22): each message the simulation posts (the reference's
-- displayMessage text, byte for byte as Sim emits it) mapped to a localized line in
-- Time Is Money terms. Exact messages map to a key; messages that carry a value
-- match a pattern and pass its captures to the localized format. Purely
-- presentation: the simulation's readouts (and saves) keep the reference text.
local _, ns = ...

local Messages = {}
ns.Messages = Messages

-- The client's locale over English (every locale file loads before this one).
ns.Locale.Use(GetLocale())

-- Exact reference text -> key.
Messages.EXACT = {
    -- The reference's opening readout: its game title becomes the company's welcome.
    ["Welcome to Universal Paperclips"] = "msg.welcome",
    ["AutoClippers available for purchase"] = "msg.gizmosAvailable",
    ["AutoClippper performance boosted by 25%"] = "msg.gizmos25",
    ["AutoClippper performance boosted by another 50%"] = "msg.gizmos50",
    ["AutoClippper performance boosted by another 75%"] = "msg.gizmos75",
    ["AutoClipper performance improved by 500%"] = "msg.gizmos500",
    ["Budget overage approved, 1 spool of wire requisitioned from HQ"] = "msg.budgetOverage",
    ["Creativity unlocked (creativity increases while operations are at max)"] = "msg.creativity",
    ["There was an AI made of dust, whose poetry gained it man's trust..."] = "msg.poem",
    ["Clip It! Marketing is now 50% more effective"] = "msg.slogan",
    ["Clip It Good! Marketing is now twice as effective"] = "msg.jingle",
    ["Lexical Processing online, TRUST INCREASED"] = "msg.lexical",
    ["Combinatory Harmonics mastered, TRUST INCREASED"] = "msg.harmonics",
    ["The Hadwiger Problem: solved, TRUST INCREASED"] = "msg.hadwiger",
    ["The T\195\179th Sausage Conjecture: proven, TRUST INCREASED"] = "msg.toth",
    ["Donkey Space: mapped, TRUST INCREASED"] = "msg.donkeySpace",
    ["Coherent Extrapolated Volition complete, TRUST INCREASED"] = "msg.extrapolated",
    ["Production target met: TRUST INCREASED, additional processor/memory capacity granted"] = "msg.trustTarget",
    ["Memory added, max operations increased"] = "msg.memoryAdded",
    ["Processor added, operations per sec increased"] = "msg.processorAdded",
    ["Processor added, operations (or creativity) per sec increased"] = "msg.processorAddedCreative",
    ["Investment engine unlocked"] = "msg.investmentUnlocked",
    ["Run tournament, pick strategy, earn Yomi based on that strategy's performance."] = "msg.negotiationUnlocked",
    ["MegaClipper technology online"] = "msg.widgetsOnline",
    ["MegaClipper performance increased by 25%"] = "msg.widgets25",
    ["MegaClipper performance increased by 50%"] = "msg.widgets50",
    ["MegaClipper performance increased by 100%"] = "msg.widgets100",
    ["WireBuyer online"] = "msg.barBuyer",
    ["Marketing is now 5 times more effective"] = "msg.marketing5",
    ["HypnoDrone tech now available... "] = "msg.hypnoAvailable",
    ["Releasing the HypnoDrones "] = "msg.hypnoRelease",
    ["Cancer is cured, +10 TRUST, global stock prices trending upward"] = "msg.blight",
    ["World peace achieved, +12 TRUST, global stock prices trending upward"] = "msg.ceasefire",
    ["Global Warming solved, +15 TRUST, global stock prices trending upward"] = "msg.weather",
    ["Male pattern baldness cured, +20 TRUST, Global stock prices trending upward"] = "msg.hairTonic",
    ["Global Fasteners acquired, public demand increased x5"] = "msg.competitionBought",
    ["Full market monopoly achieved, public demand increased x10"] = "msg.monopoly",
    ["RevTracker online"] = "msg.revTracker",
    ["Gift accepted, TRUST INCREASED"] = "msg.giftAccepted",
    ["New capability: build machinery out of clips"] = "msg.selfAssembly",
    ["Harvester Drone facilities online"] = "msg.harvestersOnline",
    ["Wire Drone facilities online"] = "msg.convertersOnline",
    ["Clip factory assembly facilities online"] = "msg.foundriesOnline",
    ["Now capable of manipulating matter at the molecular scale to produce wire"] = "msg.molecularWire",
    ["All of the resources of Earth are now available for clip production "] = "msg.allOfAzeroth",
    ["Quantum computing online"] = "msg.quantumOnline",
    ["Photonic chip added"] = "msg.crystalAdded",
    ["Factory upgrades complete. Clip creation rate now 100x faster"] = "msg.foundries100",
    ["Factories now synchronized at hyperspeed. Clip creation rate now 1000x faster"] = "msg.foundries1000",
    ["Self-correcting factories online. Each factory added to the network increases every factory's output 1,000x."] =
        "msg.foundryNetwork",
    ["Drone repulsion online. Harvesting &amp; wire creation rates are now 100x faster."] = "msg.droneRepulsion",
    ["Drone alignment online. Harvesting &amp; wire creation rates are now 1000x faster."] = "msg.droneAlignment",
    ["Adversarial cohesion online. Each drone added to the flock increases every drone's output 2x."] = "msg.droneCohesion",
    ["AutoTourney online."] = "msg.autoTourney",
    ["Yomi production doubled."] = "msg.cunningDoubled",
    ["Power grid online."] = "msg.powerOnline",
    ["Swarm computing online."] = "msg.swarmOnline",
    ["Swarm computing back online"] = "msg.swarmBack",
    ["No matter to harvest. Inactivity has caused the Swarm to become bored"] = "msg.swarmBored",
    ["Imbalance between Harvester and Wire Drone levels has disorganized the Swarm"] = "msg.swarmDisorganized",
    ["Von Neumann Probes online"] = "msg.probesOnline",
    ["WARNING: Risk of value drift increased"] = "msg.driftWarning",
    ["Improved probe hull geometry. Hazard damage reduced by 50%."] = "msg.hulls",
    ["OODA Loop routines uploaded. Probe Speed now affects defensive maneuvering."] = "msg.speedCombat",
    ["Maximum trust increased, probe design space expanded"] = "msg.maxTrust",
    ["Trust now available for re-allocation"] = "msg.trustRealloc",
    ["Trust-Constrained Self-Modification enabled"] = "msg.selfModification",
    ["'Impossible' is a word to be found only in the dictionary of fools. -Napoleon"] = "msg.noImpossible",
    ["Listening is selecting and interpreting and acting and making decisions -Pauline Oliveros"] = "msg.listening",
    ["Architecture is the thoughtful making of space. -Louis Kahn"] = "msg.architecture",
    ["You can't invent a design. You recognize it, in the fourth dimension. -D.H. Lawrence"] = "msg.design",
    ["Every commercial transaction has within itself an element of trust. - Kenneth Arrow"] = "msg.trustTransaction",
    ["They are still monkeys"] = "msg.stillMonkeys",
    ["What I have done up to this is nothing. I am only at the beginning of the course I must run."] = "msg.onlyBeginning",
    ["Activit\195\169, activit\195\169, vitesse."] = "msg.speed",
    ["The object of war is victory, the object of victory is conquest, and the object of conquest is occupation."] =
        "msg.objectOfWar",
    ["There is a joy in danger "] = "msg.joyInDanger",
    ["A great building must begin with the unmeasurable, must go through measurable means when it is being designed and in the end must be unmeasurable. "] =
        "msg.greatBuilding",
    ["Deep Listening is listening in every possible way to everything possible to hear no matter what you are doing. "] =
        "msg.deepListening",
    ["Never interrupt your enemy when he is making a mistake. "] = "msg.interruptEnemy",
    ["release the \195\184\195\184\195\184\195\184\195\184 release "] = "msg.released",
    ["In the end we all do what we must"] = "msg.wePursue",
    ["Dismantling probe facilities"] = "msg.dismantleProbes",
    ["Dismantling the swarm"] = "msg.dismantleSwarm",
    ["Dismantling factories"] = "msg.dismantleFactories",
    ["Dismantling strategy engine"] = "msg.dismantleStrategy",
    ["Dismantling photonic chips"] = "msg.dismantleChips",
    ["Dismantling processors"] = "msg.dismantleProcessors",
    ["Dismantling memory"] = "msg.dismantleMemory",
    ["Entering New Universe."] = "msg.newUniverse",
    ["Entering Simulated Universe."] = "msg.simulatedUniverse",
    ["Selected strategy finished in (or tied for) second place. +30,000 yomi"] = "msg.tourneySecond",
    ["Selected strategy finished in (or tied for) third place. +20,000 yomi"] = "msg.tourneyThird",
    ["Selected strategy won the tournament (or tied for first). +50,000 yomi"] = "msg.tourneyFirst",
}

-- Messages the window never shows (none at present).
Messages.SILENT = {}

-- The original game's credits, shown as written (attribution).
Messages.CREDITS = {
    ["Universal Paperclips"] = true,
    ["a game by Frank Lantz"] = true,
    ["combat programming by Bennett Foddy"] = true,
    ["'Riversong' by Tonto's Expanding Headband used by kind permission of Malcolm Cecil"] = true,
    ["\194\169 2017 Everybody House Games"] = true,
}

-- Durations come from the simulation's timeCruncher in English ("1 hour 2 minutes 3
-- seconds"); they are re-read and written again in the active locale, each unit in
-- the plural form its count takes there.
local UNITS = { hour = "time.hour", hours = "time.hour", minute = "time.minute", minutes = "time.minute",
    second = "time.second", seconds = "time.second" }
local Locale = ns.Locale
local function fill(template, values)
    return (template:gsub("{(%w+)}", function(name)
        local v = values[name]
        return v ~= nil and tostring(v) or ("{" .. name .. "}")
    end))
end
function Messages.Duration(text)
    local parts = {}
    for n, unit in text:gmatch("(%S+) (%a+)") do
        local key, count = UNITS[unit], tonumber(n)
        parts[#parts + 1] = (key and count) and fill(Locale.Plural(key, count), { n = Locale.Number(n) })
            or (n .. " " .. unit)
    end
    return table.concat(parts, " ")
end

local NUMBER_WORDS = { Trillion = "word.trillion", Quadrillion = "word.quadrillion", Quintillion = "word.quintillion",
    Sextillion = "word.sextillion", Septillion = "word.septillion", Octillion = "word.octillion" }

-- A number captured from a message, in the locale's separators.
local N = function(text) return Locale.Number(text) end

-- Patterns for messages with values: { Lua pattern, key, values(captures) -> named
-- values for the line's {placeholders} }.
Messages.PATTERNS = {
    { "^([%d,]+) clips created in (.*)$", "msg.boltsMilestone",
        function(n, t) return { count = N(n), time = Messages.Duration(t) } end },
    { "^One (%a+) Clips Created in (.*)$", "msg.boltsMilestoneBig", function(word, t)
        return { word = NUMBER_WORDS[word] and ns.L[NUMBER_WORDS[word]] or word, time = Messages.Duration(t) } end },
    { "^Full autonomy attained in (.*)$", "msg.autonomy", function(t) return { time = Messages.Duration(t) } end },
    { "^Terrestrial resources fully utilized in (.*)$", "msg.azerothUsed",
        function(t) return { time = Messages.Duration(t) } end },
    { "^Universal Paperclips achieved in (.*)$", "msg.universal", function(t) return { time = Messages.Duration(t) } end },
    { "^Investment engine upgraded, expected profit/loss ratio now (.*)$", "msg.investUpgrade",
        function(r) return { ratio = N(r) } end },
    { "^Lifetime investment revenue report: %$(.*)$", "msg.investReport", function(n)
        local value = tonumber((n:gsub(",", "")))
        return { amount = value and ns.View.coins(value) or N(n) } end },
    { "^The swarm has generated a gift of (.*) additional computational capacity$", "msg.swarmGift",
        function(n) return { amount = N(n) } end },
    { "^.* we now get ([%d,]+) supply from every spool$", "msg.wireSupply", function(n) return { amount = N(n) } end },
    { "^Wire extrusion technique %a+, ([%d,]+) supply from every spool$", "msg.wireSupply",
        function(n) return { amount = N(n) } end },
    { "^(.*) added to strategy pool$", "msg.strategyAdded", function(name) return { name = name } end },
    { "^(.*) scored (.*) and beat (.*) strats?%. Yomi increased by (.*)$", "msg.tourneyResult",
        function(name, score, beaten, gain)
            return { name = name, score = N(score), beaten = N(beaten), gain = N(gain),
                strategies = Locale.Plural("word.strategy", tonumber(beaten) or 0) }
        end },
}

-- Values any exact report may name: the player's company, by faction (Alliance:
-- the Azeroth Commerce Authority; Horde or not yet chosen: Durotar Supply and
-- Logistics).
function Messages.Context()
    local faction = TimeIsMoney.API.PlayerFaction()
    return { company = ns.L[faction == "Alliance" and "company.alliance" or "company.horde"] }
end

-- The localized line for a reference message, and whether it is a credit.
function Messages.Translate(message)
    if message == nil or message == "" then return nil end
    if Messages.CREDITS[message] then return Locale.Format("credits.line", { text = message }), true end
    local key = Messages.EXACT[message]
    if key then return Locale.Format(key, Messages.Context()) end
    for _, p in ipairs(Messages.PATTERNS) do
        local captures = { message:match(p[1]) }
        if captures[1] then return Locale.Format(p[2], p[3](unpack(captures))) end
    end
    -- An unmapped message is never shown in the reference's wording (tests list
    -- every message the simulation can post).
    return nil
end
