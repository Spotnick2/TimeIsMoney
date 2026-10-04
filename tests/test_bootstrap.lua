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
    local ns = {} -- the addon namespace every file receives as its second vararg
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk("TimeIsMoney", ns)
    end
    return env, captured
end

local future = { schema = 999, progress = { bolts = 123 } }
local env, captured = Load(future)
local function EventFrame(c)
    for _, frame in ipairs(c.frames) do if frame.scripts.OnEvent then return frame end end
end
local function Last() return captured.messages[#captured.messages] end
assert(env.TimeIsMoney.loaded == nil)
captured:Fire("AnotherAddon")
assert(env.TimeIsMoney.loaded == nil, "unrelated load event must be ignored")
assert(EventFrame(captured).events.ADDON_LOADED)
captured:Fire("TimeIsMoney")
assert(env.TimeIsMoney.loaded == true)
assert(not EventFrame(captured).events.ADDON_LOADED)
assert(env.TimeIsMoneyDB == future and future.schema == 999 and future.progress.bolts == 123,
    "loading must preserve existing/future saves")

assert(env.SLASH_TIMEISMONEY1 == "/timeismoney")
assert(env.SLASH_TIMEISMONEY2 == "/tim")
env.SlashCmdList.TIMEISMONEY("  StAtUs  ")
assert(captured.messages[#captured.messages - 1]:find("1.60.1.70205", 1, true))
assert(captured.messages[#captured.messages - 1]:find("16001", 1, true))
assert(Last():find("No company yet", 1, true))
env.SlashCmdList.TIMEISMONEY("help")
assert(Last():find("/tim click", 1, true))

-- Host (#18): one wakeup frame, created at load and never parented, drives the
-- simulation; a command applies at the current logical time.
local wakeups = 0
for _, frame in ipairs(captured.frames) do if frame.scripts.OnUpdate then wakeups = wakeups + 1 end end
assert(wakeups == 1, "exactly one wakeup frame")
local onUpdate
for _, frame in ipairs(captured.frames) do if frame.scripts.OnUpdate then onUpdate = frame.scripts.OnUpdate end end
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
assert(Last():find("no running game", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
assert(Last():find("Time is money, friend!", 1, true))
for _ = 1, 30 do onUpdate(nil, 1 / 60) end -- half a second
local game = env.TimeIsMoney.Host.game
assert(game.clock.now == 500, "logical time follows the wakeups in 10 ms steps: " .. game.clock.now)
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
assert(game.S.clips == 1 and game.S.wire == 999)
env.SlashCmdList.TIMEISMONEY("click btnBogus")
assert(Last():find("unknown control btnBogus", 1, true))
env.SlashCmdList.TIMEISMONEY("status")
assert(Last():find("CPU:", 1, true) and captured.messages[#captured.messages - 1]:find("1 clips", 1, true))
assert(env.TimeIsMoneyDB == future and future.progress.bolts == 123, "no save is written before #19")

local fresh, freshCapture = Load(nil)
freshCapture:Fire("TimeIsMoney")
assert(fresh.TimeIsMoneyDB == nil, "do not invent a save schema during initialization")
print("bootstrap: event filtering, load, commands and save preservation passed")
