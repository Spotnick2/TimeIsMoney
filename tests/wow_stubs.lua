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
    local allowedNil = { TimeIsMoney = true, TimeIsMoneyDB = true }
    setmetatable(env, { __index = function(_, key)
        if allowedNil[key] then return nil end
        error("Unvalidated global: " .. tostring(key), 2)
    end })
    env.CreateFrame = function(kind)
        assert(kind == "Frame")
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event)
            assert(event == "ADDON_LOADED")
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
    return env, captured
end
return { New = New }
