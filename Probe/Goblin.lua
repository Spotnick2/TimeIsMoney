-- Goblin model probe (#10). Developer-only, like the rest of TimeIsMoneyProbe.
--
-- Adapts AltStable's roster pet rendering (Plugins/Roster/AltStableRoster.lua:
-- PetFrame, ReadBox, PlacePet, MeasurePet; measured on 1.60.1.70124): a plain
-- ModelScene with one actor, SetModelByCreatureDisplayID, a narrow explicit camera,
-- a fit from the measured box, a bounded poll for that box and a token that drops
-- late answers. Display IDs come from the client (a targeted creature or an NPC ID
-- the owner names), never from guesses or Retail lists.
local _, ns = ...
local Checks, Print = ns.Checks, ns.ProbePrint

local FOV, CAMERA = 0.15, 40          -- AltStable's starting recipe
local MARGIN = 1.15                   -- headroom per framed height
local BODY_W, BODY_H = 120, 200       -- whole-body pane
local STRIP_W, STRIP_H = 96, 72       -- the storyboard's dialogue-strip portrait
local PORTRAIT = 72                   -- 2D fallback texture
local POLLS, POLL_STEP = 30, 0.1      -- box poll: about 3 s
local ANIM_SCAN = 2000                -- animation IDs checked with HasAnimation

-- posScaled: whether the client multiplies the actor's position by its scale
-- (unmeasured; /timprobe posmode compares both).
local G = { token = 0, crop = 0.4, nudge = 0, particles = false, anims = {}, animIndex = 0, posScaled = true }

local function DB()
    TimeIsMoneyProbeDB = TimeIsMoneyProbeDB or {}
    TimeIsMoneyProbeDB.goblins = TimeIsMoneyProbeDB.goblins or {}
    return TimeIsMoneyProbeDB.goblins
end

local function Build()
    local version, build = GetBuildInfo()
    return version .. "." .. build
end

-- One scene and actor, set up as AltStable's PetFrame does.
local function Pane(parent, width, height)
    local scene = CreateFrame("ModelScene", nil, parent)
    scene:SetSize(width, height)
    scene:SetCameraFieldOfView(FOV)
    scene:SetCameraNearClip(0.1)
    scene:SetCameraFarClip(100)
    scene:SetCameraPosition(CAMERA, 0, 0)
    scene:SetCameraOrientationByYawPitchRoll(math.pi, 0, 0)
    scene:EnableMouse(false)
    local actor = scene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(0, 0, 0)
    actor:SetParticleOverrideScale(0)
    scene.actor = actor
    return scene
end

local function Window()
    if G.window then return G.window end
    local w = CreateFrame("Frame", nil, UIParent)
    w:SetSize(BODY_W + STRIP_W + PORTRAIT + 40, BODY_H + 50)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    local bg = w:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.9)
    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.label:SetPoint("TOPLEFT", 8, -6)
    w.label:SetPoint("TOPRIGHT", -8, -6)
    w.label:SetJustifyH("LEFT")
    w.body = Pane(w, BODY_W, BODY_H)
    w.body:SetPoint("BOTTOMLEFT", 10, 10)
    w.strip = Pane(w, STRIP_W, STRIP_H)
    w.strip:SetPoint("BOTTOMLEFT", w.body, "BOTTOMRIGHT", 10, 0)
    local stripBg = w:CreateTexture(nil, "BORDER")
    stripBg:SetPoint("TOPLEFT", w.strip, -1, 1)
    stripBg:SetPoint("BOTTOMRIGHT", w.strip, 1, -1)
    stripBg:SetColorTexture(0.2, 0.15, 0.08, 1)
    w.portrait = w:CreateTexture(nil, "ARTWORK")
    w.portrait:SetSize(PORTRAIT, PORTRAIT)
    w.portrait:SetPoint("BOTTOMLEFT", w.strip, "BOTTOMRIGHT", 10, 0)
    -- A hidden PlayerModel answers SetCreature -> GetDisplayInfo and HasAnimation.
    w.lookup = CreateFrame("PlayerModel", nil, w)
    w.lookup:SetSize(1, 1)
    w.lookup:SetPoint("TOPRIGHT")
    w.lookup:SetAlpha(0)
    G.window = w
    return w
end

-- Scale and lift one pane's actor so the top `fraction` of the model fills it.
local function Fit(scene, box, fraction)
    local scale, offset = Checks.framing(box, scene:GetWidth(), scene:GetHeight(), CAMERA, FOV, fraction, MARGIN, G.posScaled)
    local nudge = G.nudge * box.h * (G.posScaled and 1 or scale)
    scene.actor:SetScale(scale)
    scene.actor:SetPosition(0, 0, offset + nudge)
    return scale
end

local function Refit()
    local w, box = G.window, G.box
    if not (w and box) then return end
    local bodyScale = Fit(w.body, box, 1)
    local stripScale = Fit(w.strip, box, G.crop)
    w.label:SetText(string.format("display %d   box l=%.2f w=%.2f h=%.2f   body scale %.3f\nstrip crop %.2f nudge %.2f scale %.3f   posmode %s",
        G.display, box.l, box.w, box.h, bodyScale, G.crop, G.nudge, stripScale, G.posScaled and "scaled" or "world"))
end

-- The box exists once the model has streamed in; poll briefly. A newer display or
-- close changes the token, and the late answer is dropped.
local function MeasureBox(token, tries, started)
    if token ~= G.token or not G.window then return end
    local actor = G.window.body.actor
    local r = { pcall(actor.GetActiveBoundingBox, actor) }
    local box = r[1] and Checks.readBox(unpack(r, 2, 7)) or nil
    if box then
        G.box = box
        Refit()
        Print(string.format("goblin %d: box after %.1fs (l=%.2f w=%.2f h=%.2f, model file %s). Judge texture, crop and idle by eye.",
            G.display, GetTime() - started, box.l, box.w, box.h, tostring(G.window.body.actor:GetModelFileID())))
    elseif tries > 0 then
        C_Timer.After(POLL_STEP, function() MeasureBox(token, tries - 1, started) end)
    else
        Print("goblin " .. G.display .. ": no bounding box after " .. POLLS * POLL_STEP .. "s (not loaded or not a model)")
    end
end

local function Show(display)
    local w = Window()
    G.token = G.token + 1
    G.display, G.box, G.anims, G.animIndex = display, nil, {}, 0
    w.label:SetText("display " .. display .. ": loading")
    w:Show()
    for _, scene in ipairs({ w.body, w.strip }) do
        local ok, result = pcall(scene.actor.SetModelByCreatureDisplayID, scene.actor, display)
        if not ok or result == false then Print("goblin " .. display .. ": SetModelByCreatureDisplayID -> " .. tostring(result)) end
        scene.actor:SetParticleOverrideScale(G.particles and 1 or 0)
    end
    local ok, err = pcall(SetPortraitTextureFromCreatureDisplayID, w.portrait, display)
    if not ok then Print("goblin " .. display .. ": 2D portrait error " .. tostring(err)) end
    MeasureBox(G.token, POLLS, GetTime())
end

-- Display ID of an NPC through PlayerModel:SetCreature (AltStable: answers at once
-- for a demon). Polled briefly in case it streams.
local function DisplayOfNPC(npc, onDisplay)
    local lookup = Window().lookup
    lookup:SetCreature(npc)
    local token = G.token
    local function Poll(tries)
        if token ~= G.token then return end
        local display = lookup:GetDisplayInfo()
        if display and display > 0 then onDisplay(display)
        elseif tries > 0 then C_Timer.After(POLL_STEP, function() Poll(tries - 1) end)
        else Print("npc " .. npc .. ": GetDisplayInfo stayed 0 after SetCreature") end
    end
    Poll(POLLS)
end

local function Record(entry)
    entry.build = Build()
    entry.zone = GetRealZoneText()
    local list = DB()
    list[#list + 1] = entry
end

local Commands = {}

function Commands.target()
    local guid = UnitGUID("target")
    if not guid then Print("target: no target") return end
    local name = UnitName("target")
    if UnitIsPlayer("target") then
        local race = select(2, UnitRace("target"))
        Print(string.format("target %s is a player (%s): players need a composite texture (AltStable); target an NPC", tostring(name), tostring(race)))
        return
    end
    local npc = Checks.npcFromGUID(guid)
    if not npc then Print("target " .. tostring(name) .. ": not a creature GUID (" .. tostring(guid):match("^%a+") .. ")") return end
    local creatureType = UnitCreatureType("target")
    DisplayOfNPC(npc, function(display)
        Record({ source = "target", name = name, npc = npc, display = display, creatureType = creatureType })
        Print(string.format("target %s: npc %d, display %d (%s, %s); recorded", tostring(name), npc, display, tostring(creatureType), GetRealZoneText()))
        Show(display)
    end)
end

function Commands.npc(rest)
    local npc = tonumber(rest)
    if not npc then Print("usage: /timprobe npc <npcID>") return end
    DisplayOfNPC(npc, function(display)
        Record({ source = "npc", npc = npc, display = display })
        Print(string.format("npc %d: display %d; recorded", npc, display))
        Show(display)
    end)
end

function Commands.goblin(rest)
    local display = tonumber(rest)
    if not display then Print("usage: /timprobe goblin <displayID> (from /timprobe target or npc)") return end
    Show(display)
end

-- Which animation IDs the model has, by HasAnimation on the hidden PlayerModel.
function Commands.anims()
    if not G.display then Print("anims: show a display first") return end
    local lookup, token = Window().lookup, G.token
    lookup:SetDisplayInfo(G.display)
    local function Scan(tries)
        if token ~= G.token then return end
        if not lookup:HasAnimation(0) then
            if tries > 0 then C_Timer.After(POLL_STEP, function() Scan(tries - 1) end)
            else Print("anims: the model never reported animation 0 (not loaded)") end
            return
        end
        -- HasAnimation rejects IDs past the client's enum (1866 on 70205): stop there.
        local found, limit = {}, nil
        for id = 0, ANIM_SCAN - 1 do
            local ok, has = pcall(lookup.HasAnimation, lookup, id)
            if not ok then limit = id break end
            if has then found[#found + 1] = id end
        end
        G.anims, G.animIndex = found, 0
        Print(string.format("anims for display %d: %d IDs (%s): %s", G.display, #found,
            limit and ("HasAnimation rejects " .. limit .. " and up") or ("checked 0-" .. ANIM_SCAN - 1), Checks.compactRanges(found)))
        Print("play them with /timprobe anim next (or anim <id>, anim idle); note which read as talk, approval or reaction")
    end
    Scan(POLLS)
end

function Commands.anim(rest)
    local w = G.window
    if not (w and G.display) then Print("anim: show a display first") return end
    local id
    if rest == "next" then
        if #G.anims == 0 then Print("anim next: run /timprobe anims first") return end
        G.animIndex = G.animIndex % #G.anims + 1
        id = G.anims[G.animIndex]
    elseif rest == "idle" then id = 0
    else id = tonumber(rest) end
    if not id then Print("usage: /timprobe anim <id> | next | idle") return end
    for _, scene in ipairs({ w.body, w.strip }) do scene.actor:SetAnimation(id) end
    Print("anim " .. id .. (G.animIndex > 0 and rest == "next" and string.format(" (%d of %d)", G.animIndex, #G.anims) or ""))
end

function Commands.crop(rest)
    local share, nudge = tostring(rest):match("^(%S+)%s*(%S*)$")
    share, nudge = tonumber(share), tonumber(nudge)
    if not share or share <= 0 or share > 1 then Print("usage: /timprobe crop <share 0-1 of the height> [nudge]") return end
    G.crop, G.nudge = share, nudge or G.nudge
    Refit()
    Print(string.format("crop %.2f, nudge %.2f", G.crop, G.nudge))
end

function Commands.posmode(rest)
    if rest ~= "scaled" and rest ~= "world" then Print("usage: /timprobe posmode scaled|world") return end
    G.posScaled = rest == "scaled"
    Refit()
    Print("posmode " .. rest .. ": the strip should show the head in exactly one of the two modes")
end

function Commands.particles(rest)
    G.particles = rest == "on"
    if G.window then
        for _, scene in ipairs({ G.window.body, G.window.strip }) do scene.actor:SetParticleOverrideScale(G.particles and 1 or 0) end
    end
    Print("particles " .. (G.particles and "on (scale 1)" or "off (scale 0)"))
end

-- Mean frame time over 120 frames with the window shown, then 120 with it hidden.
function Commands.frametime()
    local w = G.window
    if not (w and G.display) then Print("frametime: show a display first") return end
    local token, frames, total, phase = G.token, 0, 0, "shown"
    local results = {}
    w:Show()
    G.timer = G.timer or CreateFrame("Frame")
    G.timer:SetScript("OnUpdate", function(self, elapsed)
        if token ~= G.token then self:SetScript("OnUpdate", nil) return end
        frames, total = frames + 1, total + elapsed
        if frames < 120 then return end
        results[phase] = total / frames * 1000
        frames, total = 0, 0
        if phase == "shown" then
            phase = "hidden"
            w:Hide()
        else
            self:SetScript("OnUpdate", nil)
            w:Show()
            Print(string.format("frametime: %.2f ms with the goblin shown, %.2f ms hidden (%+.2f ms)",
                results.shown, results.hidden, results.shown - results.hidden))
        end
    end)
end

function Commands.close()
    G.token = G.token + 1
    if G.window then
        G.window.body.actor:ClearModel()
        G.window.strip.actor:ClearModel()
        G.window:Hide()
    end
    G.display, G.box = nil, nil
    Print("goblin window closed; pending loads cancelled")
end

function Commands.layers()
    local w = G.window
    if not w then Print("layers: show a display first") return end
    Print(string.format("layers: window strata %s level %d mouse %s; body level %d mouse %s; strip level %d mouse %s",
        w:GetFrameStrata(), w:GetFrameLevel(), tostring(w:IsMouseEnabled()),
        w.body:GetFrameLevel(), tostring(w.body:IsMouseEnabled()), w.strip:GetFrameLevel(), tostring(w.strip:IsMouseEnabled())))
end

for name, handler in pairs(Commands) do ns.ProbeCommands[name] = handler end
