-- Localization: every player-facing line is looked up by a stable key. Locales
-- register their strings; the client's locale (GetLocale) is chosen when one is
-- registered, and any missing key falls back to English (enUS), so a partial
-- translation never shows a hole. Add a locale file to the TOC between this file and
-- UI/Messages.lua (which calls Locale.Use), with Locale.Register("deDE", {...}).
--
-- A locale may also give:
--   plural = function(n) -> "one" | "few" | "many" | "other" ... (default: English)
--   group, decimal = the number separators (default "," and ".")
-- Lines use named placeholders, {name}, so a translation can put values in any
-- order; a key with plural forms is written key.one, key.few, key.other, ...
local _, ns = ...

local Locale = { locales = {} }
ns.Locale = Locale

function Locale.Register(code, strings)
    Locale.locales[code] = strings
end

local function englishPlural(n) return n == 1 and "one" or "other" end

-- The active strings: the client's locale over English.
function Locale.Use(code)
    local english = Locale.locales.enUS
    local chosen = Locale.locales[code]
    Locale.code = chosen and code or "enUS"
    Locale.active = chosen or english
    ns.L = setmetatable({}, { __index = function(_, key)
        local text = chosen and chosen[key]
        if text == nil then text = english[key] end
        -- A missing key shows itself rather than failing silently (tests catch it).
        if text == nil then text = "[" .. tostring(key) .. "]" end
        return text
    end })
    return Locale.code
end

-- A line with its {name} placeholders filled (values are used as given: a "%" or
-- "{" in a value is never read as a placeholder).
function Locale.Format(key, values)
    return (ns.L[key]:gsub("{(%w+)}", function(name)
        local v = values[name]
        return v ~= nil and tostring(v) or ("{" .. name .. "}")
    end))
end

-- The plural form of key for count n: key.<category> by the locale's rule, falling
-- back to key.other.
function Locale.Plural(key, n)
    local rule = (Locale.active and Locale.active.plural) or englishPlural
    local category = rule(n)
    local chosen = Locale.active and Locale.active[key .. "." .. category]
    if chosen then return chosen end
    local english = Locale.locales.enUS
    return english[key .. "." .. category] or english[key .. ".other"] or ns.L[key .. ".other"]
end

-- A number written in English form ("1,234.5") re-written with the locale's group
-- and decimal separators.
function Locale.Number(text)
    local active = Locale.active or {}
    local group, decimal = active.group or ",", active.decimal or "."
    if group == "," and decimal == "." then return text end
    return (text:gsub("[,.]", function(c) return c == "," and "\0" or decimal end):gsub("%z", group))
end
