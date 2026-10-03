local Stubs = dofile("tests/wow_stubs.lua")
local files = {}
local toc = assert(io.open("TimeIsMoney.toc", "r"))
local text = toc:read("*a")
toc:close()
assert(text:find("## Interface: 16001", 1, true))
assert(text:find("## Version: @project-version@", 1, true))
assert(text:find("## SavedVariables: TimeIsMoneyDB", 1, true))
for line in text:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
        assert(not line:find("..", 1, true) and not line:find(":", 1, true))
        files[#files + 1] = line
    end
end
assert(#files > 0)

local function Load(saved)
    local env, captured = Stubs.New(saved)
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk("TimeIsMoney")
    end
    return env, captured
end

local future = { schema = 999, progress = { bolts = 123 } }
local env, captured = Load(future)
assert(env.TimeIsMoney.loaded == nil)
captured:Fire("AnotherAddon")
assert(env.TimeIsMoney.loaded == nil, "unrelated load event must be ignored")
assert(captured.frames[1].events.ADDON_LOADED)
captured:Fire("TimeIsMoney")
assert(env.TimeIsMoney.loaded == true)
assert(not captured.frames[1].events.ADDON_LOADED)
assert(env.TimeIsMoneyDB == future and future.schema == 999 and future.progress.bolts == 123,
    "scaffold must preserve existing/future saves")

assert(env.SLASH_TIMEISMONEY1 == "/timeismoney")
assert(env.SLASH_TIMEISMONEY2 == "/tim")
env.SlashCmdList.TIMEISMONEY("  StAtUs  ")
assert(captured.messages[#captured.messages]:find("1.60.1.70205", 1, true))
assert(captured.messages[#captured.messages]:find("16001", 1, true))
env.SlashCmdList.TIMEISMONEY("help")
assert(captured.messages[#captured.messages]:find("/timeismoney", 1, true))
env.SlashCmdList.TIMEISMONEY(nil)
assert(captured.messages[#captured.messages]:find("Not playable yet", 1, true))
assert(env.TimeIsMoneyDB == future and future.progress.bolts == 123)

local fresh, freshCapture = Load(nil)
freshCapture:Fire("TimeIsMoney")
assert(fresh.TimeIsMoneyDB == nil, "do not invent a save schema during initialization")
print("bootstrap: event filtering, load, commands and save preservation passed")
