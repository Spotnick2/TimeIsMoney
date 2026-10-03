-- Developer runner: lua lua_trace_runner.lua <trace.lua> <document.json>
-- Runs the Lua simulation through a reference trace (Lua table form written by
-- tests/reference/workshop.test.cjs) and writes a runner-neutral trace document
-- (schema 2) for Tools/reference compareTraces. Not addon runtime code.
local here = arg[0]:match("^(.*)[/\\]") or "."
local root = here .. "/../.."
local RecordedRandom = dofile(here .. "/RecordedRandom.lua")

local ns = {}
local function loadSim(path) assert(loadfile(root .. "/" .. path))("TimeIsMoney", ns) end
loadSim("Sim/Reference.lua")
for _, path in ipairs(ns.Reference.files) do loadSim(path) end
local JSMath, Workshop = ns.JSMath, ns.Workshop

local trace = assert(loadfile(arg[1]))()
local events = {}
local random = RecordedRandom.new("simulation", trace.random, events)
local game = Workshop.new(random, events)
local S = game.S

-- JSON encoding matching Tools/reference/host.js encode for the projected fields.
local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function number(v)
    if v ~= v then return '{"$number":"NaN"}' end
    if v == math.huge then return '{"$number":"Infinity"}' end
    if v == -math.huge then return '{"$number":"-Infinity"}' end
    if v == 0 and 1 / v < 0 then return '{"$number":"-0"}' end
    return string.format("%.17g", v)
end
local function encode(v, isArray, out)
    local t = type(v)
    if v == JSMath.undefined then
        out[#out + 1] = '{"$number":"undefined"}'
    elseif t == "number" then
        out[#out + 1] = number(v)
    elseif t == "string" then
        out[#out + 1] = quote(v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "table" then
        if isArray or #v > 0 then
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then out[#out + 1] = "," end
                encode(v[i], false, out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = quote(k) .. ":"
                encode(v[k], false, out)
            end
            out[#out + 1] = "}"
        end
    else
        error("Unsupported value type: " .. t)
    end
end
local function json(v, isArray)
    local out = {}
    encode(v, isArray, out)
    return table.concat(out)
end

-- Projected state: every ported global except the derived battle grid. The JS
-- snapshot omits undefined globals, so this does too.
local stateKeys = {}
for k in pairs(S) do if k ~= "grid" then stateKeys[#stateKeys + 1] = k end end
table.sort(stateKeys)

local selectIds = {}
for id in pairs(game.selects) do selectIds[#selectIds + 1] = id end
table.sort(selectIds)

local checkpoints = {}
local function snapshot()
    local parts = {}
    for _, k in ipairs(stateKeys) do
        local v = S[k]
        if v ~= JSMath.undefined then parts[#parts + 1] = quote(k) .. ":" .. json(v, Workshop.arrays[k]) end
    end
    local dom = {}
    for _, id in ipairs(Workshop.buttons) do dom[#dom + 1] = quote(id) .. ':{"disabled":' .. tostring(game.disabled[id]) .. "}" end
    for i = 1, 5 do dom[#dom + 1] = quote("readout" .. i) .. ':{"html":' .. quote(game.readouts[i]) .. "}" end
    for _, id in ipairs(selectIds) do dom[#dom + 1] = quote(id) .. ':{"value":' .. quote(game.selects[id].value) .. "}" end
    return '{"state":{' .. table.concat(parts, ",") .. '},"dom":{' .. table.concat(dom, ",") ..
        '},"timers":' .. json(game.clock:describe(), true) .. ',"draws":' .. random.cursor .. "}"
end
local function checkpoint(meta)
    local event = { action = "checkpoint", index = #checkpoints }
    for k, v in pairs(meta) do event[k] = v end
    events[#events + 1] = event
    meta.json = snapshot()
    checkpoints[#checkpoints + 1] = meta
end
local function afterCallback(id) checkpoint({ kind = "callback", at = game.clock.now, id = id }) end

local ok, failure = pcall(function()
    checkpoint({ kind = "initialization", at = 0 })
    for key, value in pairs((trace.fixture or {}).globals or {}) do
        if Workshop.initial[key] == nil and not Workshop.arrays[key] then ns.Unported("fixture global " .. key, "a later slice") end
        S[key] = value
    end
    if (trace.fixture or {}).projectFlags then ns.Unported("project flag fixtures", "#8") end
    if (trace.fixture or {}).strategies then
        -- Host fixture: strats = strategies.map(i => allStrats[i]).
        local strats = {}
        for i, index in ipairs(trace.fixture.strategies) do strats[i] = S.allStrats[index + 1] end
        S.strats = strats
    end
    checkpoint({ kind = "fixture", at = game.clock.now })
    for _, command in ipairs(trace.commands or {}) do
        game:advanceTo(command.at, afterCallback, 2000)
        if command.type == "click" then
            game:click(command.id)
        elseif command.type == "value" then
            game:setValue(command.id, command.value)
        else
            ns.Unported("command type " .. tostring(command.type), "a later slice")
        end
        checkpoint({ kind = "command", at = game.clock.now, type = command.type, id = command.id })
    end
    game:advanceTo(trace["until"], afterCallback, 2000)
    checkpoint({ kind = "final", at = game.clock.now })
end)

local file = assert(io.open(arg[2], "wb"))
local function write(s) file:write(s) end
write('{"schema":2,"runner":"lua","source_sha256":' .. json(ns.Reference.source_sha256))
write(',"error":' .. (ok and "null" or quote(tostring(failure))))
local buttons, readouts, selects = {}, {}, {}
for i, id in ipairs(selectIds) do selects[i] = quote(id) end
for i, id in ipairs(Workshop.buttons) do buttons[i] = quote(id) end
for i = 1, 5 do readouts[i] = quote("readout" .. i) end
local keys = {}
for i, k in ipairs(stateKeys) do keys[i] = quote(k) end
write(',"projection":{"state":[' .. table.concat(keys, ",") .. '],"disabled":[' .. table.concat(buttons, ",") ..
    '],"html":[' .. table.concat(readouts, ",") .. '],"value":[' .. table.concat(selects, ",") .. ']}')
write(',"events":[')
for i, event in ipairs(events) do
    if i > 1 then write(",") end
    write(json(event))
end
write('],"checkpoints":[')
for i, point in ipairs(checkpoints) do
    if i > 1 then write(",") end
    local meta = {}
    for k, v in pairs(point) do if k ~= "json" then meta[k] = v end end
    write(json(meta):sub(1, -2) .. ',"json":' .. quote(point.json) .. "}")
end
write("]}")
file:close()
