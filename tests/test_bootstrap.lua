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
-- A save from a newer version blocks saving: reported, never replaced.
env.SlashCmdList.TIMEISMONEY("  StAtUs  ")
assert(captured.messages[#captured.messages - 1]:find("1.60.1.70205", 1, true))
assert(captured.messages[#captured.messages - 1]:find("16001", 1, true))
assert(Last():find("a save from a newer version (schema 999)", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
assert(Last():find("Not starting", 1, true) and env.TimeIsMoney.Host.game == nil)
captured:Logout()
assert(env.TimeIsMoneyDB == future and future.schema == 999 and future.progress.bolts == 123)
env.SlashCmdList.TIMEISMONEY("help")
assert(Last():find("/tim click", 1, true))

-- Host (#18): one wakeup frame, created at load and never parented, drives the
-- simulation; a command applies at the current logical time.
local env, captured = Load(nil)
captured:Fire("TimeIsMoney")
local wakeups, onUpdate = 0, nil
for _, frame in ipairs(captured.frames) do
    if frame.scripts.OnUpdate then wakeups, onUpdate = wakeups + 1, frame.scripts.OnUpdate end
end
assert(wakeups == 1, "exactly one wakeup frame")
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
assert(captured.messages[#captured.messages]:find("no running game", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
assert(captured.messages[#captured.messages]:find("Time is money, friend!", 1, true))
for _ = 1, 30 do onUpdate(nil, 1 / 60) end -- half a second
local game = env.TimeIsMoney.Host.game
assert(game.clock.now == 500, "logical time follows the wakeups in 10 ms steps: " .. game.clock.now)
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
assert(game.S.clips == 1 and game.S.wire == 999)
env.SlashCmdList.TIMEISMONEY("click btnBogus")
assert(captured.messages[#captured.messages]:find("unknown control btnBogus", 1, true))
env.SlashCmdList.TIMEISMONEY("status")
assert(captured.messages[#captured.messages]:find("CPU:", 1, true))
assert(captured.messages[#captured.messages - 1]:find("1 clips", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
assert(captured.messages[#captured.messages]:find("already open", 1, true), "start never replaces a company")
assert(env.TimeIsMoneyDB == nil, "nothing is written before logout")

-- Saves (#19): logout writes schema 1; the next load continues at the same logical
-- time with the same company.
captured:Logout()
local saved = env.TimeIsMoneyDB
assert(type(saved) == "table" and saved.schema == 1 and saved.company and saved.company.clock.now == 500)
local env2, captured2 = Load(saved)
captured2:Fire("TimeIsMoney")
local restored = env2.TimeIsMoney.Host.game
assert(restored and restored.clock.now == 500 and restored.S.clips == 1 and env2.TimeIsMoney.Host.running)
assert(captured2.messages[#captured2.messages]:find("reopens its ledger at 0.5 s", 1, true))

-- Unrecognized or broken saves are kept untouched, including a schema 1 company
-- missing a state field (Codex review of #55).
local damaged = { schema = 1, company = {} }
for k, v in pairs(saved.company) do damaged.company[k] = v end
damaged.company.nodes = {}
for id, node in pairs(saved.company.nodes) do damaged.company.nodes[id] = node end
local root = {}
for k, v in pairs(saved.company.nodes[saved.company.root]) do root[k] = v end
root.humanFlag = nil
damaged.company.nodes[saved.company.root] = root
for _, bad in ipairs({ "text", { schema = "one" }, { schema = 0 }, { schema = 1, company = { nodes = 5 } }, damaged }) do
    local env3, captured3 = Load(bad)
    captured3:Fire("TimeIsMoney")
    assert(env3.TimeIsMoney.Host.blocked and env3.TimeIsMoney.Host.game == nil)
    captured3:Logout()
    assert(env3.TimeIsMoneyDB == bad, "a blocked save is never replaced")
end

local fresh, freshCapture = Load(nil)
freshCapture:Fire("TimeIsMoney")
assert(fresh.TimeIsMoneyDB == nil, "do not invent a save schema during initialization")
print("bootstrap: event filtering, load, commands and save preservation passed")
