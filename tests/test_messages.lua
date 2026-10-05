-- The company's reports (#22): every message the simulation can post has a localized
-- line in Time Is Money terms; localization falls back to English key by key.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local Messages, L = ns.Messages, ns.L

-- Coverage: every literal message in the simulation's source maps to a line (or is
-- a credit). Literals reach displayMessage directly or through the projects'
-- message lists ({ "..." } passed to simple/insight/mega and friends).
local function literals(path)
    local src = assert(io.open(path, "rb")):read("*a")
    local found = {}
    local function decode(s)
        return (s:gsub("\\(%d%d?%d?)", function(d) return string.char(tonumber(d)) end):gsub('\\"', '"'))
    end
    for s in src:gmatch('displayMessage%(%s*"((.-[^\\]))"%s*%)') do found[decode(s)] = true end
    for list in src:gmatch("{%s*(\"[^}]-\")%s*}") do
        for s in list:gmatch('"((.-[^\\]))"') do found[decode(s)] = true end
    end
    return found
end
local missing, count = {}, 0
for _, file in ipairs({ "Sim/Workshop.lua", "Sim/Projects.lua", "Sim/Planet.lua", "Sim/Space.lua", "Sim/Strategy.lua",
    "Sim/Investments.lua" }) do
    for message in pairs(literals(file)) do
        -- Only messages: project lists also hold option names and the like; a message
        -- has a space and is not a bare identifier.
        if message:find(" ") and #message > 12 then
            count = count + 1
            if not Messages.Translate(message) and not Messages.SILENT[message] then missing[#missing + 1] = message end
        end
    end
end
assert(count >= 80, "found " .. count .. " messages")
assert(#missing == 0, "unmapped messages:\n" .. table.concat(missing, "\n"))

-- Messages with values: every pattern renders in Time Is Money terms.
local function says(message, expected)
    local got = Messages.Translate(message)
    assert(got == expected, message .. " -> " .. tostring(got))
end
says("500 clips created in 1 minute 5 seconds", "500 handfuls of bolts made in 1 minute 5 seconds")
says("One Trillion Clips Created in 2 hours 1 second", "One trillion handfuls of bolts made in 2 hours 1 second")
says("Full autonomy attained in 3 minutes", "Full autonomy attained in 3 minutes")
says("Universal Paperclips achieved in 9 hours", "Every handful accounted for in 9 hours")
says("Wire extrusion technique improved, 1,500 supply from every spool", "Better metal rolling: 1,500 bars' worth from every shipment.")
says("Using quantum foam annealment we now get 15,000 supply from every spool", "Better metal rolling: 15,000 bars' worth from every shipment.")
says("A100 added to strategy pool", "A100 added to the negotiation strategies.")
says("GREEDY scored 120 and beat 1 strat. Yomi increased by 120", "GREEDY scored 120 and beat 1 strategy. Cunning increased by 120.")
says("RANDOM scored 80 and beat 0 strats. Yomi increased by 80", "RANDOM scored 80 and beat 0 strategies. Cunning increased by 80.")
says("Lifetime investment revenue report: $1,234,567", "Lifetime investment revenue report: " .. ns.View.coins(1234567))
says("The swarm has generated a gift of 3 additional computational capacity",
    "The Company Network produced a breakthrough: 3 more computing capacity.")
-- Credits stay as written (attribution), marked as credits.
local text, isCredit = Messages.Translate("a game by Frank Lantz")
assert(text == "Credits: a game by Frank Lantz" and isCredit)
-- Effects as the simulation applies them: proportional to the count, in the plan's
-- names (no "drone") (consult on #22).
assert(not Messages.Translate("Adversarial cohesion online. Each drone added to the flock increases every drone's output 2x."):lower():find("drone"))
assert(Messages.Translate("Self-correcting factories online. Each factory added to the network increases every factory's output 1,000x."):find("grows with the number of foundries", 1, true))
-- Nothing in the reference's wording slips through.
assert(Messages.Translate("Welcome to Universal Paperclips") == nil and Messages.Translate("") == nil)

-- Every key the reports and beats use exists in English (a missing one shows [key]).
for _, key in pairs(Messages.EXACT) do assert(not L[key]:find("^%["), key) end
for _, p in ipairs(Messages.PATTERNS) do assert(not L[p[2]]:find("^%["), p[2]) end
for _, beat in ipairs(ns.Dialogue.BEATS) do
    assert(not L[beat[1]]:find("^%[") and not L[beat[2]]:find("^%["), beat[2])
end

-- A translation can put values in any order ({name} placeholders), use its own
-- plural rule for durations and counts, and its own number separators (consult on
-- #22).
ns.Locale.Register("xxXX", {
    ["msg.boltsMilestone"] = "After {time}, {count} handfuls were made",
    ["msg.tourneyResult"] = "+{gain} Cunning: {name} ({score}) beat {beaten} {strategies}",
    plural = function(n) return (n % 10 == 1 and n % 100 ~= 11) and "one" or ((n % 10 >= 2 and n % 10 <= 4) and "few" or "many") end,
    ["time.second.one"] = "{n} sekunda", ["time.second.few"] = "{n} sekundy", ["time.second.many"] = "{n} sekund",
    ["word.strategy.one"] = "strategie", ["word.strategy.few"] = "strategie2", ["word.strategy.many"] = "strategie5",
    group = ".", decimal = ",",
})
assert(ns.Locale.Use("xxXX") == "xxXX")
says("1,000 clips created in 2 seconds", "After 2 sekundy, 1.000 handfuls were made")
says("1,000 clips created in 5 seconds", "After 5 sekund, 1.000 handfuls were made")
says("1,000 clips created in 21 seconds", "After 21 sekunda, 1.000 handfuls were made")
says("GREEDY scored 1,200 and beat 3 strats. Yomi increased by 1,200", "+1.200 Cunning: GREEDY (1.200) beat 3 strategie2")
says("Investment engine upgraded, expected profit/loss ratio now 0.51",
    "Cartel Investments upgraded: expected profit/loss ratio now 0,51")
-- A value with "%" or "{" is used as written, never read as a placeholder.
assert(ns.Locale.Format("msg.strategyAdded", { name = "50% {name}" }) == "50% {name} added to the negotiation strategies.")
ns.Locale.Use("enUS")

-- Localization: another locale's strings win; a key it lacks falls back to English.
ns.Locale.Register("frFR", { ["beat.greeting"] = "Le temps, c'est de l'argent, l'ami !", ["time.minutes"] = "%s minutes" })
assert(ns.Locale.Use("frFR") == "frFR")
assert(ns.L["beat.greeting"] == "Le temps, c'est de l'argent, l'ami !")
assert(ns.L["beat.welcome"]:find("Welcome aboard", 1, true), "English fills what a locale lacks")
assert(ns.Locale.Use("zzZZ") == "enUS", "an unknown locale uses English")
ns.Locale.Use("enUS")

-- In the window: the newest message shows as the company's report under the beat.
env.SlashCmdList.TIMEISMONEY("start")
local game = ns.Host.game
game.readouts[1] = "AutoClippers available for purchase"
ns.Window.Refresh()
assert(h.shownText("Whirring Bronze Gizmos available for purchase."))
game.readouts[1] = "a game by Frank Lantz"
ns.Window.Refresh()
assert(h.shownText("Credits: a game by Frank Lantz"))
game.readouts[1] = "Welcome to Universal Paperclips"
ns.Window.Refresh()
assert(not h.shownText("Universal Paperclips") and not ns.Director.strip.report.shown)

print((libGlass and "messages (real LibGlass)" or "messages (LibGlass stand-in)")
    .. ": every simulation message mapped, patterns, credits, keys, locale fallback and the strip report passed")
