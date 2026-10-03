-- TimeIsMoneyProbe (#9): offline consistency of the in-game checks and the probe's
-- command and persistence logic under minimal stubs (no rendering claim).
local ns = {}
assert(loadfile("Sim/Reference.lua"))("TimeIsMoneyProbe", ns)
for _, path in ipairs(ns.Reference.files) do assert(loadfile(path))("TimeIsMoneyProbe", ns) end
assert(loadfile("Probe/Vectors.lua"))("TimeIsMoneyProbe", ns)
assert(loadfile("Probe/Checks.lua"))("TimeIsMoneyProbe", ns)
local Checks, Expected = ns.Checks, ns.ProbeVectors

-- The probe TOC loads the simulation in Sim/Reference.lua order, then the probe.
local toc, listed = assert(io.open("Probe/TimeIsMoneyProbe.toc", "r")):read("*a"), {}
for line in toc:gmatch("[^\r\n]+") do
    if line ~= "" and line:sub(1, 1) ~= "#" then listed[#listed + 1] = line end
end
local wanted = {}
for _, path in ipairs(ns.Reference.files) do wanted[#wanted + 1] = path end
for _, name in ipairs({ "Vectors.lua", "Checks.lua", "Probe.lua" }) do wanted[#wanted + 1] = name end
assert(table.concat(listed, ",") == table.concat(wanted, ","), table.concat(listed, ","))
assert(toc:find("## SavedVariables: TimeIsMoneyProbeDB", 1, true))

-- FNV-1a reference values.
assert(Checks.fnv1a("") == "811c9dc5" and Checks.fnv1a("a") == "e40c292c" and Checks.fnv1a("foobar") == "bf9cf968")

-- Offline Lua reproduces every vector and the recorded workshop digest.
local counts, failures = Checks.math(Expected.vectors, ns.JSMath)
local total = 0
for name, c in pairs(counts) do
    total = total + c[1]
    assert(c[2] == 0, name .. ": " .. table.concat(failures, "; "))
end
assert(total == #Expected.vectors and total > 1000)
local digest, draws = Checks.workshop(ns)
assert(digest == Expected.workshopDigest and draws == Expected.workshopDraws, digest .. " " .. draws)
for _, result in ipairs(Checks.environment(ns.JSMath)) do
    assert(type(result.name) == "string" and type(result.ok) == "boolean")
    -- Decimal parsing depends on the C runtime (the old 32-bit build misparses);
    -- every other fact must hold for the simulation.
    if not result.name:find("^tonumber") then assert(result.ok, result.name) end
end

-- Probe.lua under stubs: sentinel, commands and isolation from TimeIsMoneyDB.
local messages, frames = {}, {}
local env = {
    print = function(message) messages[#messages + 1] = message end,
    GetBuildInfo = function() return "1.60.1", "70170", "Oct 1 2026", 16001 end,
    SlashCmdList = {}, string = string, math = math, table = table, pairs = pairs, ipairs = ipairs,
    tostring = tostring, pcall = pcall, type = type, _VERSION = _VERSION,
    date = function() return "12:00:00" end,
    debugprofilestop = function() return 0 end,
    TimeIsMoneyProbeDB = { loadCount = 2, marker = "before" },
    CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, callback) self.onEvent = callback end
        frames[#frames + 1] = frame
        return frame
    end,
}
setmetatable(env, { __index = function(_, key)
    if key == "TimeIsMoneyDB" then return nil end
    error("Unvalidated global: " .. tostring(key), 2)
end })
local chunk = assert(loadfile("Probe/Probe.lua"))
setfenv(chunk, env)
chunk("TimeIsMoneyProbe", ns)
local function last() return messages[#messages] end
frames[1].onEvent(frames[1], "ADDON_LOADED", "Another", false)
assert(env.TimeIsMoneyProbeDB.loadCount == 2, "other addons are ignored")
frames[1].onEvent(frames[1], "ADDON_LOADED", "TimeIsMoneyProbe", false)
assert(env.TimeIsMoneyProbeDB.loadCount == 3 and last():find("previous loadCount=2", 1, true))
local slash = env.SlashCmdList.TIMEISMONEYPROBE
slash("status")
assert(messages[#messages - 2]:find("previous loadCount=2 %(nil = the file was not read%), now 3"))
assert(messages[#messages - 1]:find("marker at load=before", 1, true))
assert(last():find("TimeIsMoneyDB is untouched", 1, true))
slash("save hello")
assert(env.TimeIsMoneyProbeDB.marker == "hello @12:00:00" and env.TimeIsMoneyProbeDB.markerBuild == "1.60.1.70170")
slash("math")
assert(last():find("math: exact", 1, true), last())
slash("sim")
assert(last():find("sim: matches offline Lua", 1, true), last())
slash("bogus")
assert(last():find("/timprobe env", 1, true))
assert(rawget(env, "TimeIsMoneyDB") == nil)
print("probe: vectors, workshop digest, TOC order, sentinel and commands passed")
