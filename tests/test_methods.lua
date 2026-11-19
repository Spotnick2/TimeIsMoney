-- Every widget method the addon calls exists on that widget type in the pinned
-- build (WowTestKit's Kit.checkMethods). The exercise loads the addon (with the
-- real LibGlass when a checkout is at hand, as the window tests do), fires its
-- events, runs every /tim command, opens every panel, hovers, clicks and drags
-- every control in the three phases, and lets the Director's model load.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

local function tick(n) for _ = 1, n or 1 do WoW.tick(0.1) end end
local function slash(cmd) env.SlashCmdList.TIMEISMONEY(cmd) tick() end

-- Every script a player can reach on every shown frame: hover, press, click, drag,
-- wheel, then leave. A script may build or hide frames, so the list is taken first.
local SCRIPTS = { "OnEnter", "OnMouseDown", "OnMouseUp", "OnClick", "OnDragStart", "OnDragStop", "OnMouseWheel", "OnLeave" }
local function sweep(skip)
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        if h.visible(w) and not (skip and skip(w)) then
            for _, s in ipairs(SCRIPTS) do
                local fn = w._scripts[s]
                if fn and h.visible(w) then
                    -- A dragged frame has been laid out: its edges are known.
                    if s == "OnDragStop" and w._left == nil then w._left, w._top = 100, 700 end
                    if s == "OnMouseWheel" then fn(w, 1) else fn(w, "LeftButton", false) end
                end
            end
        end
    end
    tick()
end

WoW.fireAllRegistered()
tick()
for _, cmd in ipairs({ "", "help", "status", "start", "status", "", "", "reports", "reports", "minimap", "minimap",
    "pause", "pause", "icons", "icons", "settings", "settings", "model", "model", "anim 60", "anim x", "voice 1",
    "cue 1", "click btnMakePaperclip", "click nothing", "set btnMakePaperclip 1", "set x", "newgame", "bogus" }) do
    slash(cmd)
end

-- The Director's model streams in and is framed (the actor's methods).
captured.modelBox = { -0.42, -0.53, -0.695, 0.42, 0.53, 0.695 }
slash("model") slash("model")
tick(20)
check(Window.frame ~= nil, "the window is built")

-- Phase I: every control of the ledger, then the panels (settings, help, reports,
-- icons) and the new-game confirmation (answered no: the sweep skips its yes).
local function noNewGame(w) return Window.dialog and w == Window.dialog.yes end
Host.game.S.unusedClips, Host.game.S.funds = 1e6, 1e6
Host.update(0.02) Window.Refresh()
sweep(noNewGame)
slash("settings") sweep(noNewGame) slash("settings")
slash("help") sweep(noNewGame)
slash("reports") sweep(noNewGame) slash("reports")
slash("icons") sweep(noNewGame) slash("icons")
slash("newgame") sweep(noNewGame)

-- Phase II: manufacturing, the material pipeline, power and the network.
local S = Host.game.S
S.humanFlag, S.factoryFlag, S.tothFlag, S.wireProductionFlag = 0, 1, 1, 1
S.harvesterFlag, S.wireDroneFlag, S.swarmFlag, S.compFlag = 1, 1, 1, 1
S.project127.flag, S.project45.flag = 1, 1
S.unusedClips = 1e12
Host.update(0.02) Window.Refresh()
sweep(noNewGame)

-- Phase III: exploration, the dragonling design and combat.
S.spaceFlag, S.battleFlag = 1, 1
S.project121.flag, S.project131.flag = 1, 1
S.probeTrust, S.yomi, S.unusedClips, S.probeCount = 5, 1e9, 1e30, 1e6
Host.update(0.02) Window.Refresh()
sweep(noNewGame)
tick(10)

-- Logout writes the save.
WoW.fire("PLAYER_LOGOUT")

-- The actor's methods: the dump documents them on the model scene actor
-- ([FrameAPIModelSceneFrameActorBase], forever-api-1.60.1.70959.md), but the
-- kit's widget walk has no actor type. WowTestKit #90: each pair allowed,
-- citing the dump, and its name checked among the build's functions. The
-- Director calls two of them through pcall (UI/Director.lua), where a missing
-- method would fail silently: both must have been reached.
local ACTOR = "the model scene actor's, documented in the dump as [FrameAPIModelSceneFrameActorBase] (WowTestKit #90)"
local allow = {}
local functions = Kit.data("functions")
for pair in pairs(WoW.methodsCalled) do
    local wtype, method = pair:match("^([%w_]+):([%w_]+)$")
    if wtype == "ModelSceneActor" then
        allow[pair] = ACTOR
        check(functions[method], "an actor method the build documents: " .. method)
    end
end
check(WoW.methodsCalled["ModelSceneActor:SetModelByCreatureDisplayID"], "the Director's pcalled model load was reached")
check(WoW.methodsCalled["ModelSceneActor:GetActiveBoundingBox"], "the Director's pcalled box read was reached")

local recorded = Kit.checkMethods({ allow = allow })
-- The floor: what the exercise records today (143 with the real library, 109 with
-- the stand-in, whose material makes fewer calls), rounded down.
check(recorded >= (libGlass and 140 or 105), "the exercise reached the windows (" .. recorded .. " recorded)")

eq(h.acceptKnownStrays(), 2, "the known stray help line, once per /tim help (#114)")
done(libGlass and "test_methods (real LibGlass)" or "test_methods (LibGlass stand-in)")
