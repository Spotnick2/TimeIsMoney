-- The Director's strip (#22): the speaker's picture, name and line under the cards.
-- The Director is Gazlowe (creature display 7052, docs/MODELS.md): a live ModelScene
-- with idle running, framed on the measured 0.40 / 1.15 head crop, or the client's
-- 2D portrait when the model is off or does not load. After the takeover the
-- Ledger's reports carry the company mark, and the Unlisted Director's letters a
-- dragonling. Purely cosmetic: no randomness, no game state, and its only timers
-- poll the model's box for a bounded time, dropped by token on hide or change.
local _, ns = ...

local Director = {}
ns.Director = Director
TimeIsMoney.Director = Director

Director.DISPLAY = 7052                 -- Gazlowe (npc 3391), owner's choice (#10)
Director.WIDTH, Director.HEIGHT = 96, 72 -- the storyboard strip, as measured (#10)
Director.CROP, Director.MARGIN = 0.40, 1.15
Director.FOV, Director.CAMERA = 0.15, 40
Director.POLLS, Director.POLL_STEP = 30, 0.1 -- the box poll: about 3 s
Director.STRIP = 84                      -- the strip's height in the window
Director.modelEnabled = true             -- /tim model toggles (session; settings are #23)

-- Framing for a camera at distance d whose field of view spans the frame's larger
-- side (AltStable's recipe, measured; Probe/Checks.lua): the top `fraction` of the
-- model's height fills the frame with `margin` headroom. The client scales the
-- actor's position with the actor (measured on 70205), so the offset is divided by
-- the scale. Returns the actor scale and vertical offset.
function Director.Framing(box, frameW, frameH, d, fov, fraction, margin)
    local span = 2 * d * math.tan(fov / 2)
    local viewH = (frameW >= frameH) and (span * frameH / frameW) or span
    local scale = viewH / (box.h * fraction * margin)
    local offset = -(1 - fraction) / 2 * box.h * scale
    return scale, offset / scale
end

-- GetActiveBoundingBox: six numbers on measured Forever, or two vectors.
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

-- Builds the strip under parent (the window's content), with the Glass helpers.
function Director.Build(parent, font)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(Director.STRIP)
    -- The picture: a mouse-disabled scene (input falls through), a 2D portrait, and
    -- the icon for the Ledger and the Unlisted Director.
    local scene = CreateFrame("ModelScene", nil, strip)
    scene:SetSize(Director.WIDTH, Director.HEIGHT)
    scene:SetPoint("LEFT", strip, "LEFT", 0, 0)
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
    strip.scene = scene
    strip.portrait = strip:CreateTexture(nil, "ARTWORK")
    strip.portrait:SetSize(Director.HEIGHT, Director.HEIGHT)
    strip.portrait:SetPoint("CENTER", scene, "CENTER", 0, 0)
    strip.speaker = font(10, "LEFT")
    strip.speaker:SetPoint("TOPLEFT", strip, "TOPLEFT", Director.WIDTH + 12, -8)
    strip.line = font(12, "LEFT")
    strip.line:SetPoint("TOPLEFT", strip.speaker, "BOTTOMLEFT", 0, -4)
    strip.line:SetWordWrap(true)
    strip:SetScript("OnHide", function() Director.Cancel() end)
    Director.strip = strip
    Director.token, Director.state = 0, "none" -- none | loading | live | portrait
    return strip
end

-- Drops any pending box poll (hidden, replaced, or no longer the Director).
function Director.Cancel()
    Director.token = (Director.token or 0) + 1
    if Director.state == "loading" then Director.state = "none" end
end

local function ShowPortrait()
    local strip = Director.strip
    strip.scene:Hide()
    local ok = pcall(SetPortraitTextureFromCreatureDisplayID, strip.portrait, Director.DISPLAY)
    if not ok then strip.portrait:SetTexture(ns.Assets.FALLBACK) end
    strip.portrait:Show()
    Director.state = "portrait"
end

-- The model streams in; its box appears after a moment. Poll a bounded number of
-- times; a newer token (hide, change) drops the answer. No box: the portrait.
local function Measure(token, tries)
    if token ~= Director.token then return end
    local actor = Director.strip.scene.actor
    local r = { pcall(actor.GetActiveBoundingBox, actor) }
    local box = r[1] and Director.ReadBox(unpack(r, 2, 7)) or nil
    if box then
        local scale, offset = Director.Framing(box, Director.WIDTH, Director.HEIGHT, Director.CAMERA, Director.FOV,
            Director.CROP, Director.MARGIN)
        actor:SetScale(scale)
        actor:SetPosition(0, 0, offset)
        Director.state = "live"
    elseif tries > 0 then
        C_Timer.After(Director.POLL_STEP, function() Measure(token, tries - 1) end)
    else
        Director.failed = true -- this session keeps the portrait; no retry per redraw
        ShowPortrait()
    end
end

local function ShowModel()
    local strip = Director.strip
    strip.portrait:Hide()
    strip.scene:Show()
    if Director.state == "live" or Director.state == "loading" then return end
    if Director.failed then
        if Director.state ~= "portrait" then ShowPortrait() end
        return
    end
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
    local token = Director.token
    C_Timer.After(Director.POLL_STEP, function() Measure(token, Director.POLLS) end)
end

local MARKS = { [ "The Ledger" ] = "clips", [ "The Unlisted Director" ] = "probes" }

-- Redraws the strip for this speaker and line (width: the strip's width).
function Director.Update(speaker, line, width)
    local strip = Director.strip
    strip:SetShown(speaker ~= nil)
    if not speaker then return end
    strip:SetWidth(width)
    strip.line:SetWidth(width - Director.WIDTH - 16)
    strip.speaker:SetText(string.upper(speaker))
    strip.line:SetText(line)
    if speaker == ns.Dialogue.DIRECTOR then
        if Director.modelEnabled then ShowModel() elseif Director.state ~= "portrait" then ShowPortrait() end
    else
        -- The Director has gone: drop the model and any poll; show the mark.
        if Director.state ~= "none" then
            Director.Cancel()
            strip.scene.actor:ClearModel()
            strip.scene:Hide()
            Director.state = "none"
        end
        strip.portrait:SetTexture((ns.Assets.IdentityIcon(MARKS[speaker])))
        strip.portrait:Show()
    end
end

-- /tim model: the live model or the 2D portrait.
function Director.ToggleModel()
    Director.modelEnabled = not Director.modelEnabled
    if Director.state ~= "none" then
        Director.Cancel()
        Director.strip.scene.actor:ClearModel()
        Director.state = "none"
    end
    return Director.modelEnabled
end
