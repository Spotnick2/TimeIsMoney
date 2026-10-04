-- Allowlist from forever-api-1.60.1.70205.md; no rendering/persistence claim.
local function New(saved)
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
    function Widget:CreateFontString()
        local fs = setmetatable({ scripts = {}, shown = true }, { __index = Widget })
        captured.fontStrings[#captured.fontStrings + 1] = fs
        return fs
    end
    captured.fontStrings, captured.widgets = {}, {}
    env.UIParent = setmetatable({ scripts = {}, shown = true }, { __index = Widget })
    env.GameTooltip = setmetatable({ scripts = {}, shown = false }, { __index = Widget })
    function env.GameTooltip:SetOwner() end
    function env.GameTooltip:AddLine() end
    -- LibGlass-1.0 stand-in: the calls the window makes, recorded. The library's own
    -- tests cover the material; here only the API shape matters.
    captured.glass = { applied = 0 }
    local glass = {}
    function glass.Apply(host, size)
        assert(size == "large" or size == "small", "glass size")
        captured.glass.applied = captured.glass.applied + 1
        return { size = size }
    end
    function glass.Font(parent, size, justify) return parent:CreateFontString() end
    function glass.Bar(parent, height) return env.CreateFrame("StatusBar", nil, parent) end
    function glass.Inset() return 8 end
    function glass.ContentLevel(host) return host:GetFrameLevel() + 2 end
    function glass.SetBar(bar, max, value) bar.max, bar.value = max, value end
    env.LibStub = function(name)
        assert(name == "LibGlass-1.0")
        return { New = function(self) assert(self ~= nil, "colon call") return glass end }
    end
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
    return env, captured
end
return { New = New }
