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
        pcall = pcall,
        GetServerTime = function() return 1790000000 end,
        debugprofilestop = function() captured.clock = (captured.clock or 0) + 0.01 return captured.clock end,
    }
    local allowedNil = { TimeIsMoney = true, TimeIsMoneyDB = true, TimeIsMoneyWindow = true }
    setmetatable(env, { __index = function(_, key)
        if allowedNil[key] then return nil end
        error("Unvalidated global: " .. tostring(key), 2)
    end })
    -- Widgets the window builds (#20): methods confirmed in the API dump, with the
    -- state they set kept for assertions. Stubs cannot prove pixels.
    local Widget = {}
    local methods = {
        "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata", "SetToplevel", "SetClampedToScreen",
        "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "SetMotionScriptsWhileDisabled", "SetJustifyH", "SetWordWrap", "SetStatusBarColor",
        -- What LibGlass-1.0 r1 calls (its own test_methods checks them against the dump).
        "AddMaskTexture", "Play", "SetAlpha", "SetBlendMode", "SetClipsChildren", "SetColorTexture",
        "SetDuration", "SetFont", "SetFromAlpha", "SetGradient", "SetHorizTile", "SetMinMaxValues",
        "SetOffset", "SetShadowColor", "SetShadowOffset", "SetSmoothing", "SetStartDelay",
        "SetStatusBarTexture", "SetTexture", "SetTextureSliceMargins", "SetTextureSliceMode", "SetToAlpha",
        "SetValue", "SetVertTile", "SetVertexColor", "Stop",
    }
    for _, m in ipairs(methods) do Widget[m] = function() end end
    function Widget:SetScript(kind, fn) self.scripts[kind] = fn end
    function Widget:SetSize(w, h) self.width, self.height = w, h end
    function Widget:SetWidth(w) self.width = w end
    function Widget:SetHeight(h) self.height = h end
    function Widget:GetHeight() return self.height or 0 end
    function Widget:Show() self.shown = true end
    function Widget:Hide() self.shown = false end
    function Widget:SetShown(v) self.shown = not not v end
    function Widget:IsShown() return self.shown end
    function Widget:SetFrameLevel(l) self.level = l end
    function Widget:GetFrameLevel() return self.level or 1 end
    function Widget:SetEnabled(v) self.enabled = not not v end
    function Widget:IsEnabled() return self.enabled end
    function Widget:SetText(t) self.text = t end
    function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
    local function child(kind)
        return setmetatable({ kind = kind, scripts = {}, shown = true }, { __index = Widget })
    end
    function Widget:CreateTexture() return child("Texture") end
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
    captured.fontStrings, captured.widgets = {}, {}
    env.UIParent = setmetatable({ scripts = {}, shown = true, height = 768 }, { __index = Widget })
    env.GameTooltip = setmetatable({ scripts = {}, shown = false }, { __index = Widget })
    function env.GameTooltip:SetOwner() end
    function env.GameTooltip:AddLine() end
    captured.glass = { applied = 0 }
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
            assert(kind == "Frame" or kind == "Button" or kind == "StatusBar", "widget kind " .. tostring(kind))
            local w = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true },
                { __index = Widget })
            if name then env[name] = w end
            captured.widgets[#captured.widgets + 1] = w
            return w
        end
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event)
            assert(event == "ADDON_LOADED" or event == "PLAYER_LOGOUT")
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
