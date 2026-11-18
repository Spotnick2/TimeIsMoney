local Stubs = dofile("tests/wow_stubs.lua")
local files = {}
local toc = assert(io.open("TimeIsMoney.toc", "r"))
local text = toc:read("*a")
toc:close()
check(text:find("## Interface: 16001", 1, true))
check(text:find("## Version: @project-version@", 1, true))
check(text:find("## SavedVariables: TimeIsMoneyDB", 1, true))
check(text:find("## X-Curse-Project-ID: 1733557\n", 1, true), "the CurseForge project ID")
check(text:find("## X-Wago-ID: RNL47eNo\n", 1, true), "the Wago project ID")
for line in text:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    -- The embedded LibGlass is the stubs' stand-in (its own repo tests the library).
    if line ~= "" and line:sub(1, 1) ~= "#" and line:gsub("\\", "/"):sub(1, 5) ~= "Libs/" then
        check(not line:find("..", 1, true) and not line:find(":", 1, true))
        files[#files + 1] = line
    end
end
check(#files > 0)
-- WowTestKit's own TOC checks on top: interface, version token, every listed .lua
-- file exists, each line listed once.
Kit.checkToc("TimeIsMoney.toc")

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
    for _, frame in ipairs(c.frames) do if frame._scripts.OnEvent and frame._events.PLAYER_LOGOUT then return frame end end
end
local function Last() return captured.messages[#captured.messages] end
check(env.TimeIsMoney.loaded == nil)
captured:Fire("AnotherAddon")
check(env.TimeIsMoney.loaded == nil, "unrelated load event must be ignored")
check(EventFrame(captured)._events.ADDON_LOADED)
captured:Fire("TimeIsMoney")
check(env.TimeIsMoney.loaded == true)
check(not EventFrame(captured)._events.ADDON_LOADED)
check(env.TimeIsMoneyDB == future and future.schema == 999 and future.progress.bolts == 123,
    "loading must preserve existing/future saves")

check(env.SLASH_TIMEISMONEY1 == "/timeismoney")
check(env.SLASH_TIMEISMONEY2 == "/tim")
-- A save from a newer version blocks saving: reported, never replaced.
env.SlashCmdList.TIMEISMONEY("  StAtUs  ")
check(captured.messages[#captured.messages - 1]:find("1.60.1.70338", 1, true))
check(captured.messages[#captured.messages - 1]:find("16001", 1, true))
check(Last():find("a save from a newer version (schema 999)", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
check(Last():find("Not starting", 1, true) and env.TimeIsMoney.Host.game == nil)
captured:Logout()
check(env.TimeIsMoneyDB == future and future.schema == 999 and future.progress.bolts == 123)
env.SlashCmdList.TIMEISMONEY("help")
check(Last():find("/tim click", 1, true))

-- Host (#18): one wakeup frame, created at load and never parented, drives the
-- simulation; a command applies at the current logical time.
local env, captured = Load(nil)
captured:Fire("TimeIsMoney")
local wakeups, onUpdate = 0, nil
for _, frame in ipairs(captured.frames) do
    if frame._scripts.OnUpdate then wakeups, onUpdate = wakeups + 1, frame._scripts.OnUpdate end
end
check(wakeups == 1, "exactly one wakeup frame")
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
check(captured.messages[#captured.messages]:find("no company (/tim start)", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
check(captured.messages[#captured.messages]:find("Time is money, friend!", 1, true))
for _ = 1, 30 do onUpdate(nil, 1 / 60) end -- half a second
local game = env.TimeIsMoney.Host.game
check(game.clock.now == 500, "logical time follows the wakeups in 10 ms steps: " .. game.clock.now)
env.SlashCmdList.TIMEISMONEY("click btnMakePaperclip")
check(game.S.clips == 1 and game.S.wire == 999)
env.SlashCmdList.TIMEISMONEY("click btnBogus")
check(captured.messages[#captured.messages]:find("unknown control btnBogus", 1, true))
env.SlashCmdList.TIMEISMONEY("status")
check(captured.messages[#captured.messages]:find("CPU:", 1, true))
check(captured.messages[#captured.messages - 1]:find("1 clips", 1, true))
env.SlashCmdList.TIMEISMONEY("start")
check(captured.messages[#captured.messages]:find("already open", 1, true), "start never replaces a company")
check(env.TimeIsMoneyDB == nil, "nothing is written before logout")

-- Saves (#19): logout writes schema 1; the next load continues at the same logical
-- time with the same company.
captured:Logout()
local saved = env.TimeIsMoneyDB
check(type(saved) == "table" and saved.schema == 1 and saved.company and saved.company.clock.now == 500)
local env2, captured2 = Load(saved)
captured2:Fire("TimeIsMoney")
local restored = env2.TimeIsMoney.Host.game
check(restored and restored.clock.now == 500 and restored.S.clips == 1 and env2.TimeIsMoney.Host.running)
check(captured2.messages[#captured2.messages]:find("reopens its ledger at 0.5 s", 1, true))

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
-- And one whose first ship has lost a coordinate (a nested record).
local shipless = { schema = 1, company = {} }
for k, v in pairs(saved.company) do shipless.company[k] = v end
shipless.company.nodes = {}
for id, node in pairs(saved.company.nodes) do shipless.company.nodes[id] = node end
local shipsNode = saved.company.nodes[saved.company.nodes[saved.company.root].ships.r]
local firstShip = {}
for k, v in pairs(saved.company.nodes[shipsNode[1].r]) do firstShip[k] = v end
firstShip.x = nil
shipless.company.nodes[shipsNode[1].r] = firstShip
for _, bad in ipairs({ "text", { schema = "one" }, { schema = 0 }, { schema = 1, company = { nodes = 5 } }, damaged,
    shipless }) do
    local env3, captured3 = Load(bad)
    captured3:Fire("TimeIsMoney")
    check(env3.TimeIsMoney.Host.blocked and env3.TimeIsMoney.Host.game == nil)
    captured3:Logout()
    check(env3.TimeIsMoneyDB == bad, "a blocked save is never replaced")
end

local fresh, freshCapture = Load(nil)
freshCapture:Fire("TimeIsMoney")
check(fresh.TimeIsMoneyDB == nil, "do not invent a save schema during initialization")

eq(Stubs.acceptKnownStrays(), 1, "the known stray help line, once per /tim help (#114)")

-- Covered: event filtering, load, commands and save preservation.
done("test_bootstrap")
