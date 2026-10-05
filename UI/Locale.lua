-- Localization: every player-facing line is looked up by a stable key. Locales
-- register their strings; the client's locale (GetLocale) is chosen when one is
-- registered, and any missing key falls back to English (enUS), so a partial
-- translation never shows a hole. Add a locale with Locale.Register("deDE", {...}).
local _, ns = ...

local Locale = { locales = {} }
ns.Locale = Locale

function Locale.Register(code, strings)
    Locale.locales[code] = strings
end

-- The active strings: the client's locale over English.
function Locale.Use(code)
    local english = Locale.locales.enUS
    local chosen = Locale.locales[code]
    Locale.code = chosen and code or "enUS"
    ns.L = setmetatable({}, { __index = function(_, key)
        local text = chosen and chosen[key]
        if text == nil then text = english[key] end
        -- A missing key shows itself rather than failing silently (tests catch it).
        if text == nil then text = "[" .. tostring(key) .. "]" end
        return text
    end })
    return Locale.code
end
