-- Developer-only recorded random stream for parity runs; not addon runtime code.
-- Mirrors Tools/reference/host.js RandomStream: finite values in [0,1), zero-based
-- ordinals, a call-site label per draw, and an error instead of wrapping.
local RecordedRandom = {}
RecordedRandom.__index = RecordedRandom

local function isFiniteFraction(value)
    return type(value) == "number" and value == value and value >= 0 and value < 1
end

function RecordedRandom.new(name, values, log)
    if type(name) ~= "string" or name == "" then error("A stream name is required", 2) end
    if type(values) ~= "table" or #values == 0 then
        error("An explicit finite random stream in [0,1) is required", 2)
    end
    for i = 1, #values do
        if not isFiniteFraction(values[i]) then
            error("An explicit finite random stream in [0,1) is required", 2)
        end
    end
    return setmetatable({ name = name, values = values, cursor = 0, log = log or {} }, RecordedRandom)
end

function RecordedRandom:draw(site, at)
    if type(site) ~= "string" or site == "" then error("Every draw needs a call-site label", 2) end
    if self.cursor >= #self.values then
        error(self.name .. " random stream exhausted at draw " .. self.cursor .. " (" .. site .. ")", 2)
    end
    local value = self.values[self.cursor + 1]
    self.log[#self.log + 1] = {
        action = "draw", at = at, stream = self.name, ordinal = self.cursor, site = site, value = value,
    }
    self.cursor = self.cursor + 1
    return value
end

-- Reads the recorded stream document {"schema":1,"stream":...,"values":[...]}
-- written by the Node fixtures. Numbers keep their shortest JSON spelling, which
-- converts to the same double in both runtimes.
function RecordedRandom.parse(text)
    if not text:match('"schema"%s*:%s*1[,}%s]') then error("Unsupported recorded stream schema", 2) end
    local name = text:match('"stream"%s*:%s*"([%w%-]+)"')
    local body = text:match('"values"%s*:%s*%[([^%]]*)%]')
    if not name or not body then error("Malformed recorded stream document", 2) end
    local values = {}
    for token in body:gmatch("[^,%s]+") do
        local value = tonumber(token)
        if not value then error("Malformed recorded value: " .. token, 2) end
        values[#values + 1] = value
    end
    return RecordedRandom.new(name, values)
end

local function encodeValue(value)
    if type(value) == "number" then
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then return string.format("%d", value) end
        return string.format("%.17g", value)
    end
    return '"' .. tostring(value):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end

-- Encodes draw events in the runner-neutral trace event form (fixed key order).
function RecordedRandom.encodeLog(log)
    local parts = {}
    for i, event in ipairs(log) do
        local fields = {}
        for _, key in ipairs({ "action", "at", "stream", "ordinal", "site", "value" }) do
            if event[key] ~= nil then fields[#fields + 1] = '"' .. key .. '":' .. encodeValue(event[key]) end
        end
        parts[i] = "{" .. table.concat(fields, ",") .. "}"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

return RecordedRandom
