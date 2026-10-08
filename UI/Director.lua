-- The Director's strip (#22): the speaker's picture, name and line under the cards.
-- The Director is Gazlowe (creature display 7052, docs/MODELS.md): a live ModelScene
-- with idle running, framed on the measured 0.40 / 1.15 head crop, or the client's
-- 2D portrait when the model is off or does not load. After the takeover the
-- Ledger's reports carry the company mark, and the Unlisted Director's letters a
-- dragonling. Purely cosmetic: no randomness, no game state and no timers of its
-- own. The window's redraw ticks the box poll, so a hidden window polls nothing.
local _, ns = ...

local Director = {}
ns.Director = Director
TimeIsMoney.Director = Director

Director.DISPLAY = 7052                  -- Gazlowe (npc 3391), owner's choice (#10)
-- Gazlowe's measured height (#10, box 0.84 x 1.06 x 1.39). The live box follows
-- the idle pose and differs between loads (PORTING-TBC-TO-FOREVER, 70205), so the
-- framing uses this height and the live box only says "the model is in".
Director.MODEL_HEIGHT = 1.39
-- The scene is wider than the measured 96x72 strip crop: the idle animation turns
-- Gazlowe's head past a 96 px frame and it clipped (owner, 2026-10-05). The framing
-- recomputes the zoom from the frame, so he keeps his size with room to move; the
-- margin leaves headroom for the ears.
-- The scene is also taller than the framed crop (owner, 2026-10-08): the talk
-- animation dips the head below an 84 px frame, other animations raise it. The
-- margin grows with the height, so his head keeps its size and place (the visible
-- band stays centred on the top 40 % of the model) with room above and below.
Director.WIDTH, Director.HEIGHT = 136, 120
Director.FRAMED_HEIGHT = 84                       -- the height the 1.30 margin was picked at
Director.CROP, Director.MARGIN = 0.40, 1.30 * 120 / 84
Director.PORTRAIT = 84                            -- the 2D fallback keeps its measured size
Director.FOV, Director.CAMERA = 0.15, 40
Director.POLLS, Director.POLL_STEP = 30, 0.1 -- the box poll: about 3 s
Director.REPORT_LINES, Director.REPORT_ALPHA = 3, { 1, 0.7, 0.45 }
Director.MIN_STRIP = Director.HEIGHT + 8  -- the strip's height with the 3D model
-- The strip's height when the line is short: the 3D model's scene, or the 84 px
-- picture (the 2D portrait, the Ledger's and the Unlisted Director's marks).
function Director.MinStrip(speaker)
    if speaker == ns.Dialogue.DIRECTOR and ns.Settings.values.model and not Director.failed then return Director.MIN_STRIP end
    return Director.PORTRAIT + 8
end
-- The model and the voice follow the saved settings (UI/Settings.lua).
local function setting(key) return ns.Settings.values[key] end
-- "Time is money, friend!": a goblin NPC greeting from the client's own files
-- (sound/creature/goblinmalegruffnpc/goblinmalegruffnpcgreeting01.ogg, file 550785;
-- picked by ear by the owner, 2026-10-05, from the community listfile).
Director.GREETING_SOUND = 550785
-- Gazlowe's lines (#90; owner-supplied goblin NPC voice files, 2026-10-08; each to
-- be confirmed in the client with /tim voice <id>, as 550785 was). Greetings rotate
-- when the window opens; the deal lines answer a report now and then.
Director.VOICE = {
    greet = { 550785, 550786, 550773 }, -- "Time is money, friend!", "Ah! Potential customers.", "Yo!"
    deal = { 550772, 550784, 550782 },  -- "I get the best deals anywhere.", "Do I have a deal for you!", "I got what you need."
}
-- The report cue (#90): a soft sound, Gazlowe's talk animation, the newest line
-- fading in. At most one cue every CUE_COOLDOWN seconds; a deal line at most every
-- DEAL_COOLDOWN, only while the window shows. The sound kit and the animation are
-- unverified in the client until the owner picks them (/tim cue, /tim anim).
Director.CUE_SOUNDKIT = 120     -- SOUNDKIT.LOOT_WINDOW_COIN_SOUND
-- The talk animation, measured on Gazlowe in the client (docs/MODELS.md forbids
-- guessing IDs from Retail lists; /tim anim <id> tries others).
Director.TALK_ANIM = 60 -- Talk: picked by the owner in the client (2026-10-08)
Director.TALK_SECONDS = 2.5
Director.CUE_COOLDOWN, Director.DEAL_COOLDOWN = 4, 60
Director.FADE_SECONDS = 0.5
Director.GREET_TALK_WINDOW = 1 -- a model that loads later than this after the line stays idle
Director.clock, Director.lastCue, Director.lastDeal = 0, -math.huge, -math.huge
Director.greetIndex, Director.dealIndex = 0, 0
Director.state, Director.token = "none", 0 -- none | loading | live | portrait

-- Framing for a camera at distance d whose field of view spans the frame's larger
-- side (AltStable's recipe, measured; Probe/Checks.lua's framing with the
-- position scaled by the actor, as measured on 70205, and a drift test keeps the
-- two equal): the top `fraction` of the model fills the frame with `margin`
-- headroom. Returns the actor scale and vertical offset.
function Director.Framing(box, frameW, frameH, d, fov, fraction, margin)
    local span = 2 * d * math.tan(fov / 2)
    local viewH = (frameW >= frameH) and (span * frameH / frameW) or span
    local scale = viewH / (box.h * fraction * margin)
    local offset = -(1 - fraction) / 2 * box.h * scale
    return scale, offset / scale
end

-- GetActiveBoundingBox: six numbers on measured Forever, or two vectors (the same
-- reading as Probe/Checks.lua's readBox, kept equal by a drift test).
function Director.ReadBox(...)
    local a = { ... }
    local x0, y0, z0, x1, y1, z1
    if type(a[1]) == "table" and type(a[2]) == "table" then
        x0, y0, z0, x1, y1, z1 = a[1].x, a[1].y, a[1].z, a[2].x, a[2].y, a[2].z
    else
        x0, y0, z0, x1, y1, z1 = a[1], a[2], a[3], a[4], a[5], a[6]
    end
    x0, y0, z0, x1, y1, z1 = tonumber(x0), tonumber(y0), tonumber(z0), tonumber(x1), tonumber(y1), tonumber(z1)
    if not (x0 and y0 and z0 and x1 and y1 and z1) or z1 - z0 <= 0.001 then return nil end
    return { l = x1 - x0, w = y1 - y0, h = z1 - z0 }
end

-- Builds the strip under parent (the window's content). font(frame, size, justify)
-- makes a glass font on the given frame: the strip's text belongs to the strip, so
-- hiding the strip hides it.
function Director.Build(parent, font)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(Director.MIN_STRIP)
    -- The picture: a mouse-disabled scene (input falls through), a 2D portrait, and
    -- the icon for the Ledger and the Unlisted Director.
    local scene = CreateFrame("ModelScene", nil, strip)
    scene:SetSize(Director.WIDTH, Director.HEIGHT)
    scene:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -4)
    scene:SetCameraFieldOfView(Director.FOV)
    scene:SetCameraNearClip(0.1)
    scene:SetCameraFarClip(100)
    scene:SetCameraPosition(Director.CAMERA, 0, 0)
    scene:SetCameraOrientationByYawPitchRoll(math.pi, 0, 0)
    scene:EnableMouse(false)
    local actor = scene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(0, 0, 0)
    actor:SetParticleOverrideScale(0) -- particles escaped the frame in AltStable
    scene.actor = actor
    scene:Hide()
    strip.scene = scene
    strip.portrait = strip:CreateTexture(nil, "ARTWORK")
    strip.portrait:SetSize(Director.PORTRAIT, Director.PORTRAIT)
    -- The 84 px picture at the top of the picture column, inside the short strip
    -- (PORTRAIT + 8): never centred on the taller 3D scene (Codex review of #93).
    strip.portrait:SetPoint("TOP", strip, "TOPLEFT", Director.WIDTH / 2, -4)
    -- The speaker's name (copper), then the Director's role (muted) beside it.
    strip.speaker = font(strip, 13, "LEFT")
    strip.speaker:SetPoint("TOPLEFT", strip, "TOPLEFT", Director.WIDTH + 12, -8)
    local copper, muted = ns.Window.COPPER, ns.Window.MUTED -- the window's palette
    strip.speaker:SetTextColor(copper[1], copper[2], copper[3])
    strip.role = font(strip, 10, "LEFT")
    strip.role:SetPoint("BOTTOMLEFT", strip.speaker, "BOTTOMRIGHT", 8, 1)
    strip.role:SetTextColor(muted[1], muted[2], muted[3])
    strip.line = font(strip, 12, "LEFT")
    strip.line:SetPoint("TOPLEFT", strip.speaker, "BOTTOMLEFT", 0, -3)
    strip.line:SetWordWrap(true)
    -- The company's latest reports (#83), newest first, older ones fading; muted
    -- and smaller: the Director's line leads. A click opens the full history.
    strip.reports = {}
    for i = 1, Director.REPORT_LINES do
        local r = font(strip, 10, "LEFT")
        r:SetWordWrap(true)
        r:SetTextColor(muted[1], muted[2], muted[3])
        r:SetAlpha(Director.REPORT_ALPHA[i])
        strip.reports[i] = r
    end
    strip.report = strip.reports[1]
    strip.reportArea = CreateFrame("Button", nil, strip)
    strip.reportArea:SetScript("OnClick", function() ns.Window.ToggleReports() end)
    local function reportsTip(self)
        local tip = ns.Window.Tip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:SetText(ns.L["reports.title"], 1, 1, 1)
        tip:AddLine(ns.L["reports.open"], muted[1], muted[2], muted[3])
        tip:Show()
    end
    strip.reportArea:SetScript("OnEnter", reportsTip)
    strip.reportArea:SetScript("OnLeave", function() ns.Window.Tip():Hide() end)
    -- Clicking Gazlowe (or the mark in his place) opens the reports too. The scene
    -- itself stays mouse-disabled; this button over the picture takes the click and
    -- still drags the window.
    strip.pictureArea = CreateFrame("Button", nil, strip)
    strip.pictureArea:SetAllPoints(scene) -- re-fitted to the picture shown (Update)
    ns.Window.Draggable(strip.pictureArea)
    strip.pictureArea:SetScript("OnClick", function() ns.Window.ToggleReports() end)
    strip.pictureArea:SetScript("OnEnter", reportsTip)
    strip.pictureArea:SetScript("OnLeave", function() ns.Window.Tip():Hide() end)
    strip:SetScript("OnHide", function() Director.Cancel() end)
    Director.strip = strip
    return strip
end

-- Drops any pending box poll (hidden, replaced, or no longer the Director).
function Director.Cancel()
    Director.talkWhenLive = nil
    Director.token = Director.token + 1
    Director.poll = nil
    if Director.state == "loading" then Director.state = "none" end
end

local function ShowPortrait()
    Director.talkWhenLive = nil
    local strip = Director.strip
    strip.scene:Hide()
    local ok = pcall(SetPortraitTextureFromCreatureDisplayID, strip.portrait, Director.DISPLAY)
    if not ok then strip.portrait:SetTexture(ns.Assets.FALLBACK) end
    strip.portrait:Show()
    Director.state = "portrait"
end

-- The window's redraw ticks this while a load is pending: look for the box every
-- POLL_STEP, at most POLLS times. Once it is in, frame the model from its measured
-- height; with no box, the portrait for the session (until /tim model retries).
function Director.Tick(elapsed)
    Director.clock = Director.clock + elapsed
    local strip = Director.strip
    if Director.talkUntil and Director.clock >= Director.talkUntil then
        Director.talkUntil = nil
        if strip and Director.state == "live" then strip.scene.actor:SetAnimation(0) end -- idle
    end
    if Director.fadeIn and strip then
        Director.fadeIn = Director.fadeIn + elapsed
        local a = math.min(1, Director.fadeIn / Director.FADE_SECONDS)
        strip.reports[1]:SetAlpha(a * Director.REPORT_ALPHA[1])
        if a >= 1 then Director.fadeIn = nil end
    end
    local poll = Director.poll
    if not poll or poll.token ~= Director.token then return end
    poll.elapsed = poll.elapsed + elapsed
    if poll.elapsed < Director.POLL_STEP then return end
    poll.elapsed = 0
    local actor = Director.strip.scene.actor
    local r = { pcall(actor.GetActiveBoundingBox, actor) }
    if r[1] and Director.ReadBox(unpack(r, 2, 7)) then
        local scale, offset = Director.Framing({ h = Director.MODEL_HEIGHT }, Director.WIDTH, Director.HEIGHT,
            Director.CAMERA, Director.FOV, Director.CROP, Director.MARGIN)
        actor:SetScale(scale)
        actor:SetPosition(0, 0, offset)
        Director.state, Director.poll = "live", nil
        -- A greeting spoken while the model loaded: he talks now that he is in.
        if Director.talkWhenLive then
            Director.talkWhenLive = nil
            if Director.clock - (Director.greetAt or -math.huge) <= Director.GREET_TALK_WINDOW then Director.Talk() end
        end
    else
        poll.tries = poll.tries - 1
        if poll.tries <= 0 then
            Director.poll, Director.failed = nil, true
            ShowPortrait()
        end
    end
end

local function ShowModel()
    local strip = Director.strip
    if Director.failed then
        if Director.state ~= "portrait" then ShowPortrait() end
        return
    end
    strip.portrait:Hide()
    strip.scene:Show()
    if Director.state == "live" or Director.state == "loading" then return end
    Director.Cancel()
    local actor = strip.scene.actor
    actor:ClearModel()
    actor:SetScale(1)
    actor:SetPosition(0, 0, 0)
    local ok, result = pcall(actor.SetModelByCreatureDisplayID, actor, Director.DISPLAY)
    if not ok or result == false then
        Director.failed = true
        ShowPortrait()
        return
    end
    Director.state = "loading"
    Director.poll = { token = Director.token, tries = Director.POLLS, elapsed = 0 }
end

local function DropModel()
    Director.talkWhenLive = nil
    Director.Cancel()
    Director.strip.scene.actor:ClearModel()
    Director.strip.scene:Hide()
    Director.state = "none"
end

local MARKS = { ["speaker.ledger"] = "clips", ["speaker.unlisted"] = "probes" }

-- Redraws the strip for this speaker and line (localization keys) and the latest
-- reports (localized texts, newest first; may be empty). width: the strip's width.
-- Returns the strip's height: at least MIN_STRIP, more when the text wraps further.
function Director.Update(speaker, line, width, reports)
    local strip = Director.strip
    strip:SetShown(speaker ~= nil)
    if not speaker then return 0 end
    local L = ns.L
    strip:SetWidth(width)
    strip.line:SetWidth(width - Director.WIDTH - 16)

    -- The Director by name with his role; the others by their name alone.
    local isDirector = speaker == ns.Dialogue.DIRECTOR
    strip.speaker:SetText(isDirector and L["speaker.directorName"] or L[speaker])
    strip.role:SetShown(isDirector)
    if isDirector then strip.role:SetText(L[speaker]) end
    strip.line:SetText(L[line])
    reports = reports or {}
    local textWidth = width - Director.WIDTH - 16
    local anchor, reportHeight = strip.line, 0
    for i, r in ipairs(strip.reports) do
        local text = reports[i]
        r:SetShown(text ~= nil)
        if text then
            r:SetWidth(textWidth)
            r:SetText(text)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -6 or -2)
            reportHeight = reportHeight + (i == 1 and 6 or 2) + r:GetStringHeight()
            anchor = r
        end
    end
    strip.reportArea:SetShown(reports[1] ~= nil)
    if reports[1] then
        strip.reportArea:ClearAllPoints()
        strip.reportArea:SetPoint("TOPLEFT", strip.reports[1], "TOPLEFT", 0, 0)
        strip.reportArea:SetSize(textWidth, reportHeight)
    end
    if speaker == ns.Dialogue.DIRECTOR then
        if setting("model") then ShowModel() elseif Director.state ~= "portrait" then ShowPortrait() end
    else
        -- The Director has gone (or never spoke this session): no model, the mark.
        if Director.state ~= "none" or strip.scene:IsShown() then DropModel() end
        strip.portrait:SetTexture((ns.Assets.IdentityIcon(MARKS[speaker])))
        strip.portrait:Show()
    end
    -- The click area covers the picture actually shown: the scene, or the portrait.
    strip.pictureArea:ClearAllPoints()
    strip.pictureArea:SetAllPoints(strip.scene:IsShown() and strip.scene or strip.portrait)
    local height = math.max(Director.MinStrip(speaker), 8 + 16 + 3 + strip.line:GetStringHeight() + reportHeight + 8)
    strip:SetHeight(height)
    return height
end

-- Opening the window while the Director is speaking: he greets the player aloud,
-- on the dialog channel (the player's dialog volume and mute apply).
function Director.Greet(speaker)
    if speaker == ns.Dialogue.DIRECTOR and setting("voice") then
        -- The greetings in turn: never the same line twice in a row.
        local lines = Director.VOICE.greet
        Director.greetIndex = Director.greetIndex % #lines + 1
        TimeIsMoney.API.PlaySoundFile(lines[Director.greetIndex], "Dialog")
        -- He says it: the talk animation, now or as soon as the model is in (if
        -- that is still while he speaks: GREET_TALK_WINDOW seconds).
        Director.greetAt = Director.clock
        if not Director.Talk() then Director.talkWhenLive = Director.state == "loading" or nil end
    end
end

-- Gazlowe's talk animation, back to idle after TALK_SECONDS (live model only).
function Director.Talk(anim)
    local strip = Director.strip
    anim = anim or Director.TALK_ANIM
    if not strip or Director.state ~= "live" or not anim then return false end
    strip.scene.actor:SetAnimation(anim)
    Director.talkUntil = Director.clock + Director.TALK_SECONDS
    return true
end

-- A new report while the window shows (#90): the newest line fades in; at most one
-- cue per CUE_COOLDOWN, Gazlowe talks, and either a deal line (his voice, at most
-- once per DEAL_COOLDOWN) or the soft report sound plays.
function Director.Report(speaker)
    local strip = Director.strip
    if not strip then return end
    strip.reports[1]:SetAlpha(0)
    Director.fadeIn = 0
    if Director.clock - Director.lastCue < Director.CUE_COOLDOWN then return end
    Director.lastCue = Director.clock
    local gazlowe = speaker == ns.Dialogue.DIRECTOR
    if gazlowe then Director.Talk() end
    if gazlowe and setting("voice") and Director.clock - Director.lastDeal >= Director.DEAL_COOLDOWN then
        Director.lastDeal = Director.clock
        local lines = Director.VOICE.deal
        Director.dealIndex = Director.dealIndex % #lines + 1
        TimeIsMoney.API.PlaySoundFile(lines[Director.dealIndex], "Dialog")
    elseif setting("reportSound") then
        TimeIsMoney.API.PlaySound(Director.CUE_SOUNDKIT)
    end
end

-- /tim model: the live model or the 2D portrait. Turning it on retries a model that
-- failed to load. Works before the window exists (it applies when the strip does).
function Director.ToggleModel()
    return Director.SetModel(not setting("model"))
end

-- The model setting (saved): on retries a model that failed to load.
function Director.SetModel(on)
    ns.Settings.Set("model", on)
    Director.failed = nil
    if Director.strip and Director.state ~= "none" then DropModel() end
    return on
end
