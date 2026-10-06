-- Settings (#23): presentation preferences, saved with the account's data. They
-- never reach the simulation: nothing here changes a formula, a timer or a draw.
-- Saved values are checked one by one; a damaged or unknown one falls back to its
-- default and never blocks the save.
local _, ns = ...

local Settings = {}
ns.Settings = Settings
TimeIsMoney.Settings = Settings

Settings.SCALE_MIN, Settings.SCALE_MAX, Settings.SCALE_STEP = 0.6, 1.5, 0.1
Settings.DEFAULTS = { model = true, voice = true, scale = 1, helpSeen = false, point = nil }
-- point: the window's top-left corner in UIParent units (unaffected by the window's
-- own scale), as { "TOPLEFT", "BOTTOMLEFT", x, y }.

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
-- NaN through JSMath: in WoW's Lua NaN compares equal (and >= and <=) to anything.
local function finite(v)
    return type(v) == "number" and not ns.JSMath.isNaN(v) and v ~= math.huge and v ~= -math.huge
end
local VALID = {
    model = function(v) return type(v) == "boolean" end,
    voice = function(v) return type(v) == "boolean" end,
    helpSeen = function(v) return type(v) == "boolean" end,
    scale = function(v) return finite(v) and v >= Settings.SCALE_MIN - 1e-9 and v <= Settings.SCALE_MAX + 1e-9 end,
    point = function(v)
        return type(v) == "table" and POINTS[v[1]] and POINTS[v[2]] and finite(v[3]) and finite(v[4])
    end,
}

-- The current values: defaults, then whatever valid values were saved.
function Settings.Load(saved)
    local values = {}
    for k, v in pairs(Settings.DEFAULTS) do values[k] = v end
    if type(saved) == "table" then
        for k, valid in pairs(VALID) do
            if saved[k] ~= nil and valid(saved[k]) then values[k] = saved[k] end
        end
    end
    local function copyPoint(p) return p and { p[1], p[2], p[3], p[4] } or nil end
    values.point = copyPoint(values.point)
    Settings.values = values
    Settings.copyPoint = copyPoint
    return values
end

-- What is saved: plain values only (no frames or closures). The host asks for it at
-- logout (Host.settings is this function).
function Settings.Data()
    local v = Settings.values
    return { model = v.model, voice = v.voice, scale = v.scale, helpSeen = v.helpSeen, point = Settings.copyPoint(v.point) }
end
ns.Host.settings = Settings.Data

-- Changes one value (checked).
function Settings.Set(key, value)
    assert(VALID[key], "unknown setting " .. tostring(key))
    if value ~= nil and not VALID[key](value) then return false end
    Settings.values[key] = value
    return true
end

-- The window scale, stepped within its bounds.
function Settings.StepScale(delta)
    local v = Settings.values.scale + delta * Settings.SCALE_STEP
    v = math.floor(v * 10 + 0.5) / 10
    v = math.max(Settings.SCALE_MIN, math.min(Settings.SCALE_MAX, v))
    Settings.Set("scale", v)
    return v
end

Settings.Load(nil)
