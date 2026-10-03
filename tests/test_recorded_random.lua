local RecordedRandom = dofile("tests/reference/RecordedRandom.lua")

local function fails(pattern, fn, ...)
    local ok, message = pcall(fn, ...)
    assert(not ok and tostring(message):find(pattern), tostring(message))
end

local log = {}
local simulation = RecordedRandom.new("simulation", { 0.17, 0.43 }, log)
local cosmetic = RecordedRandom.new("cosmetic", { 0.5 })
assert(simulation:draw("combat.js:717:22", 0) == 0.17)
assert(cosmetic:draw("glass:shimmer", 0) == 0.5)
assert(simulation:draw("main.js:704:14", 10) == 0.43)
assert(#log == 2 and log[1].ordinal == 0 and log[2].ordinal == 1)
assert(log[2].site == "main.js:704:14" and log[2].at == 10 and log[2].stream == "simulation")
assert(#cosmetic.log == 1 and cosmetic.log[1].stream == "cosmetic", "cosmetic draws stay off the simulation log")
fails("exhausted at draw 2 %(main.js:1490:18%)", simulation.draw, simulation, "main.js:1490:18", 20)
fails("call%-site label", simulation.draw, simulation, nil, 20)
fails("explicit finite", RecordedRandom.new, "simulation", {})
fails("explicit finite", RecordedRandom.new, "simulation", { 1 })
fails("explicit finite", RecordedRandom.new, "simulation", { 0 / 0 })

local parsed = RecordedRandom.parse('{"schema":1,"stream":"simulation","values":[0.17,0.30000000000000004,5e-324,0]}')
assert(parsed.name == "simulation" and #parsed.values == 4)
assert(parsed.values[1] == 0.17 and parsed.values[2] == 0.1 + 0.2 and parsed.values[3] > 0 and parsed.values[4] == 0)
fails("schema", RecordedRandom.parse, '{"schema":2,"stream":"simulation","values":[0.5]}')
fails("Malformed recorded value", RecordedRandom.parse, '{"schema":1,"stream":"simulation","values":[0.5,"x"]}')

assert(RecordedRandom.encodeLog(log) ==
    '[{"action":"draw","at":0,"stream":"simulation","ordinal":0,"site":"combat.js:717:22","value":0.17000000000000001},'
    .. '{"action":"draw","at":10,"stream":"simulation","ordinal":1,"site":"main.js:704:14","value":0.42999999999999999}]')
print("recorded random: labeled ordinals, separate cosmetic stream, exhaustion and stream documents passed")
