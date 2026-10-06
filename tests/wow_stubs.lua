-- Allowlist from forever-api-1.60.1.70205.md; no rendering/persistence claim.
-- libGlass: a LibGlass-1.0 checkout to load for real (its XML's files, called as
-- the client would), or nil for the recording stand-in below.
local function New(saved, libGlass)
    local captured = { frames = {}, messages = {} }
    local env = {
        TimeIsMoneyDB = saved, SlashCmdList = {}, _VERSION = _VERSION,
        tostring = tostring,
        print = function(message) captured.messages[#captured.messages + 1] = message end,
        GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", 16001 end,
        -- Standard Lua the simulation and host use (test_sim.lua enforces Sim's set).
        math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type,
        tonumber = tonumber, error = error, setmetatable = setmetatable, next = next, select = select,
        pcall = pcall, assert = assert,
        GetServerTime = function() return 1790000000 end,
        debugprofilestop = function() captured.clock = (captured.clock or 0) + 0.01 return captured.clock end,
    }
    local allowedNil = { TimeIsMoney = true, TimeIsMoneyDB = true, TimeIsMoneyWindow = true, TimeIsMoneyIcons = true, TimeIsMoneyConfirm = true, TimeIsMoneyHelp = true,
        TimeIsMoneySettings = true }
    setmetatable(env, { __index = function(_, key)
        if allowedNil[key] then return nil end
        error("Unvalidated global: " .. tostring(key), 2)
    end })
    -- Widgets the window builds (#20): methods confirmed in the API dump, with the
    -- state they set kept for assertions. Stubs cannot prove pixels.
    local Widget = {}
    local methods = {
        "ClearAllPoints", "SetAllPoints", "SetToplevel", "SetClampedToScreen",
        "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetUserPlaced",
        "SetMotionScriptsWhileDisabled", "SetJustifyH", "SetWordWrap", "SetStatusBarColor",
        -- The Director's ModelScene (#22; measured in the client by the #10 probe).
        "SetCameraFieldOfView", "SetCameraNearClip", "SetCameraFarClip", "SetCameraPosition",
        "SetCameraOrientationByYawPitchRoll", "SetUseCenterForOrigin", "SetParticleOverrideScale",
        -- What LibGlass-1.0 r1 calls (its own test_methods checks them against the dump).
        "AddMaskTexture", "Play", "SetBlendMode", "SetClipsChildren",
        "SetDuration", "SetFont", "SetFromAlpha", "SetGradient", "SetHorizTile", "SetMinMaxValues",
        "SetOffset", "SetShadowColor", "SetShadowOffset", "SetSmoothing", "SetStartDelay",
        "SetStatusBarTexture", "SetTextureSliceMargins", "SetTextureSliceMode", "SetToAlpha",
        "SetValue", "SetVertTile", "SetVertexColor", "Stop",
    }
    for _, m in ipairs(methods) do Widget[m] = function() end end
    function Widget:SetScript(kind, fn) self.scripts[kind] = fn end
    function Widget:SetSize(w, h) self.width, self.height = w, h end
    function Widget:SetWidth(w) self.width = w end
    function Widget:SetHeight(h) self.height = h end
    function Widget:GetHeight() return self.height or 0 end
    function Widget:GetWidth() return self.width or 0 end
    function Widget:SetScale(s) self.scale = s end
    function Widget:Show() self.shown = true end
    -- Hiding a shown widget fires its OnHide, as the client does.
    function Widget:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function Widget:SetShown(v) self.shown = not not v end
    function Widget:IsShown() return self.shown end
    function Widget:SetFrameLevel(l) self.level = l end
    function Widget:Raise() captured.raised = self end
    function Widget:SetFrameStrata(s) self.strata = s end
    function Widget:GetScale() return self.scale or 1 end
    function Widget:GetLeft() return self.left or 100 end
    function Widget:GetTop() return self.top or 700 end
    function Widget:GetFrameLevel() return self.level or 1 end
    function Widget:SetEnabled(v) self.enabled = not not v end
    function Widget:IsEnabled() return self.enabled end
    function Widget:SetText(t) self.text = t end
    function Widget:GetText() return self.text end
    -- About 6 px per character at the window's sizes (stubs cannot measure text).
    function Widget:GetStringWidth() return #tostring(self.text or "") * 6 end
    -- Wrapped height: 14 px per line at the set width (stubs cannot measure text).
    function Widget:GetStringHeight()
        local perLine = math.max(1, math.floor((self.width or 1000) / 6))
        return 14 * math.max(1, math.ceil(#tostring(self.text or "") / perLine))
    end
    function Widget:SetPoint(...) self.point = { ... } end
    function Widget:SetAlpha(a) self.alpha = a end
    function Widget:SetTexture(t) self.texture = t end
    function Widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
    local function child(kind)
        return setmetatable({ kind = kind, scripts = {}, shown = true }, { __index = Widget })
    end
    -- The model actor: tests choose whether a display loads (captured.modelOK) and the
    -- box it reports once streamed (captured.modelBox, six numbers).
    function Widget:CreateActor()
        local actor = child("Actor")
        function actor:SetModelByCreatureDisplayID(id)
            self.display = id
            captured.modelLoads = (captured.modelLoads or 0) + 1
            return captured.modelOK ~= false
        end
        function actor:ClearModel() self.display = nil end
        function actor:SetScale(v) self.scaleValue = v end
        function actor:SetPosition(x, y, z) self.position = { x, y, z } end
        function actor:GetActiveBoundingBox()
            if self.display and captured.modelBox then return unpack(captured.modelBox) end
        end
        captured.actor = actor
        return actor
    end
    function Widget:CreateTexture()
        local t = child("Texture")
        t.parent = self
        captured.textures[#captured.textures + 1] = t
        return t
    end
    function Widget:CreateMaskTexture() return child("MaskTexture") end
    function Widget:CreateAnimationGroup() return child("AnimationGroup") end
    function Widget:CreateAnimation() return child("Animation") end
    function Widget:GetStatusBarTexture()
        self.barTexture = self.barTexture or child("Texture")
        return self.barTexture
    end
    function Widget:CreateFontString()
        local fs = setmetatable({ scripts = {}, shown = true, parent = self }, { __index = Widget })
        captured.fontStrings[#captured.fontStrings + 1] = fs
        return fs
    end
    captured.fontStrings, captured.widgets, captured.textures = {}, {}, {}
    env.UIParent = setmetatable({ scripts = {}, shown = true, width = 1024, height = 768 }, { __index = Widget })
    env.GameTooltip = setmetatable({ scripts = {}, shown = false }, { __index = Widget })
    function env.GameTooltip:SetOwner() end
    function env.GameTooltip:AddLine() end
    captured.glass = { applied = 0 }
    -- Icons (#21): the client resolves item icons once their data is loaded; tests
    -- choose which items are known (captured.itemIcons) and fire the load result.
    captured.itemIcons, captured.requested = {}, {}
    env.C_Item = {
        GetItemIconByID = function(id) return captured.itemIcons[id] end,
        RequestLoadItemDataByID = function(id) captured.requested[#captured.requested + 1] = id end,
    }
    env.C_Spell = { GetSpellTexture = function(id) return 100000 + id end }
    -- C_Timer.After: callbacks queue until the test runs them (captured:RunTimers()).
    captured.timers = {}
    env.C_Timer = { After = function(_, fn) captured.timers[#captured.timers + 1] = fn end }
    function captured:RunTimers()
        local due = self.timers
        self.timers = {}
        for _, fn in ipairs(due) do fn() end
        return #due
    end
    env.SetPortraitTextureFromCreatureDisplayID = function(texture, id) texture.portraitDisplay = id end
    env.GetLocale = function() return captured.locale or "enUS" end
    env.UnitFactionGroup = function() return captured.faction or "Horde" end
    captured.sounds = {}
    env.PlaySoundFile = function(id, channel) captured.sounds[#captured.sounds + 1] = { id, channel } return true end
    env.unpack = unpack
    captured.now = 0
    env.GetTime = function() return captured.now end
    function captured:ItemLoaded(id, success)
        for _, frame in ipairs(self.frames) do
            if frame.events.ITEM_DATA_LOAD_RESULT then frame.scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", id, success) end
        end
    end
    if libGlass then
        -- The real library: what it needs beyond the widgets above.
        env._G, env.strmatch, env.assert, env.rawget = env, string.match, assert, rawget
        env.Enum = {}
        env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        env.hooksecurefunc = function(object, method, hook)
            local original = object[method]
            object[method] = function(...)
                local results = { original(...) }
                hook(...)
                return unpack(results)
            end
        end
        env.unpack = unpack
        allowedNil.LibStub = true
    end
    local libFiles
    if libGlass then
        local xml = assert(io.open(libGlass .. "/LibGlass-1.0.xml", "rb")):read("*a"):gsub("<!%-%-.-%-%->", "")
        libFiles = {}
        for file in xml:gmatch('<Script%s+file="([^"]+)"') do libFiles[#libFiles + 1] = libGlass .. "/" .. file:gsub("\\", "/") end
    end
    -- LibGlass-1.0 stand-in: the calls the window makes, recorded. The library's own
    -- tests cover the material; here only the API shape matters.
    local glass = {}
    function glass.Apply(host, size)
        assert(size == "large" or size == "small", "glass size")
        captured.glass.applied = captured.glass.applied + 1
        return { size = size, top = env.CreateFrame("Frame", nil, host) }
    end
    function glass.Font(parent, size, justify) return parent:CreateFontString() end
    function glass.Bar(parent, height) return env.CreateFrame("StatusBar", nil, parent) end
    function glass.Inset(size) return size == "small" and 3 or 6 end -- LibGlass r1 SIZES
    function glass.ContentLevel(host) return host:GetFrameLevel() + 2 end
    function glass.SetBar(bar, max, value) bar.max, bar.value = max, value end
    if not libGlass then env.LibStub = function(name)
        assert(name == "LibGlass-1.0")
        return { New = function(self) assert(self ~= nil, "colon call") return glass end }
    end end
    env.CreateFrame = function(kind, name, parent)
        if kind ~= "Frame" or parent ~= nil or name ~= nil then
            assert(kind == "Frame" or kind == "Button" or kind == "StatusBar" or kind == "ModelScene",
                "widget kind " .. tostring(kind))
            local w = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true },
                { __index = Widget })
            if name then env[name] = w end
            captured.widgets[#captured.widgets + 1] = w
            return w
        end
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event)
            assert(event == "ADDON_LOADED" or event == "PLAYER_LOGOUT" or event == "ITEM_DATA_LOAD_RESULT")
            self.events[event] = true
            return true
        end
        function frame:UnregisterEvent(event)
            self.events[event] = nil
            return true
        end
        function frame:SetScript(kind, callback)
            assert(kind == "OnEvent" or kind == "OnUpdate")
            self.scripts[kind] = callback
        end
        captured.frames[#captured.frames + 1] = frame
        return frame
    end
    function captured:Fire(addonName)
        for _, frame in ipairs(self.frames) do
            if frame.events.ADDON_LOADED then
                frame.scripts.OnEvent(frame, "ADDON_LOADED", addonName, false)
            end
        end
    end
    function captured:Logout()
        for _, frame in ipairs(self.frames) do
            if frame.events.PLAYER_LOGOUT then frame.scripts.OnEvent(frame, "PLAYER_LOGOUT") end
        end
    end
    return env, captured, libFiles
end
return { New = New }
