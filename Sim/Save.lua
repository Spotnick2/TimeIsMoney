-- Saved games (#19): the whole simulation as plain data a SavedVariables writer can
-- store, and back. Pure Lua: no client calls; Host.lua decides when to write.
--
-- Game state is a graph: active projects are the same tables as S.projectN, the
-- strategy pool points into allStrats, tournament results point at strategies. A
-- SavedVariables writer copies tables by value, so every table becomes a numbered
-- node and every reference {r = id}. Safe integers are stored as numbers; other
-- numbers (fractions, huge values, NaN, infinities, -0) as their exact IEEE words
-- {w = "hhhhhhhhllllllll"}, and JavaScript's undefined as {u = 1}. The battle grid
-- is rebuilt (each update refills it); timers are saved by kind (Sim/Scheduler.lua).
local _, ns = ...
ns = ns or {}

local JSMath, Workshop, Scheduler, Battle = ns.JSMath, ns.Workshop, ns.Scheduler, ns.Battle
local Game = Workshop.Game
local floor = math.floor

local Save = {}
Save.SCHEMA = 1
ns.Save = Save

local SAFE = 2 ^ 53
-- Plain numbers stay within 14 significant digits, so even a writer that prints
-- %.14g keeps them exact; everything else is stored as IEEE words.
local PLAIN = 1e14

-- Eight hex digits of a 32-bit word. WoW's string.format raises on integer overflow
-- (measured for %d of 2^31, #9), so each 16-bit half is formatted on its own.
local function hex8(n)
    n = n % 4294967296
    local low = n % 65536
    return string.format("%04x%04x", (n - low) / 65536, low)
end

local function encodeNumber(x)
    if not JSMath.isNaN(x) and x == floor(x) and x > -PLAIN and x < PLAIN then
        if x ~= 0 then return x end
        -- -0 keeps its sign below (toWords gives its high word signed or unsigned).
        local hi = JSMath.toWords(x)
        if not (hi < 0 or hi >= 0x80000000) then return x end
    end
    local hi, lo = JSMath.toWords(x)
    return { w = hex8(hi) .. hex8(lo) }
end

local function decodeNumber(text)
    if type(text) ~= "string" or not text:match("^%x+$") or #text ~= 16 then
        error("Malformed saved number", 0)
    end
    return JSMath.fromWords(tonumber(text:sub(1, 8), 16), tonumber(text:sub(9, 16), 16))
end

-- Keys: strings, or integers (arrays, 1-based; the grid's 0-based rows are skipped).
local function checkKey(k)
    local t = type(k)
    if t == "string" then return k end
    if t == "number" and k == floor(k) and k > -SAFE and k < SAFE then return k end
    error("Unsaveable table key " .. tostring(k), 0)
end

-- The scheduler's numbers go through the same exact encoding as the state.
local CLOCK_FIELDS, TIMER_FIELDS = { "now", "nextId", "order" }, { "id", "delay", "due", "order" }
local function mapClock(clock, f)
    local out = { timers = {} }
    for _, k in ipairs(CLOCK_FIELDS) do out[k] = f(clock[k]) end
    for i, t in ipairs(clock.timers) do
        local copy = { kind = t.kind, ["repeat"] = t["repeat"] }
        for _, k in ipairs(TIMER_FIELDS) do copy[k] = f(t[k]) end
        out.timers[i] = copy
    end
    return out
end

-- The game as plain data. random is the host's stream state ({s1, s2, count}).
function Save.encode(game, random)
    local ids, nodes = {}, {}
    local function value(v)
        if v == JSMath.undefined then return { u = 1 } end
        local t = type(v)
        if t == "number" then return encodeNumber(v) end
        if t == "string" or t == "boolean" then return v end
        if t == "table" then
            local id = ids[v]
            if not id then
                id = #nodes + 1
                ids[v] = id
                nodes[id] = false
                local node = {}
                for k, x in pairs(v) do node[checkKey(k)] = value(x) end
                nodes[id] = node
            end
            return { r = id }
        end
        error("Unsaveable value of type " .. t, 0)
    end
    local S = game.S
    local grid = S.grid
    S.grid = nil
    local ok, root = pcall(value, S)
    S.grid = grid
    if not ok then error(root, 0) end
    local controls = { disabled = {}, projectElements = {}, readouts = {}, selects = {}, ranges = {} }
    for id, v in pairs(game.disabled) do controls.disabled[id] = v end
    for id, v in pairs(game.projectElements) do controls.projectElements[id] = v end
    for i = 1, 5 do controls.readouts[i] = game.readouts[i] end
    for id, select in pairs(game.selects) do
        local options = {}
        for i, o in ipairs(select.options) do options[i] = o end
        controls.selects[id] = { options = options, value = select.value }
    end
    for id, range in pairs(game.ranges) do controls.ranges[id] = range.value end
    controls.resultsTableDisplay = game.resultsTableDisplay -- read by autoTourney
    return {
        schema = Save.SCHEMA,
        source = ns.Reference.source_sha256["main.js"],
        root = root.r,
        nodes = nodes,
        clock = mapClock(game.clock:save(), encodeNumber),
        random = random and { s1 = random.s1, s2 = random.s2, count = random.count } or nil,
        controls = controls,
    }
end

local function expect(cond, what)
    if not cond then error("Malformed save: " .. what, 0) end
end

-- Timer cadences that never change (a damaged save is refused, not run off-beat).
local SHAPES = {
    battle = { 16, true }, portfolio = { 100, true }, stockShop = { 1000, true }, stockSell = { 2500, true },
    pick = { 100, true }, main = { 10, true }, slow = { 100, true }, blink = { 30, true }, longBlink = { 32, true },
    tourneyClear = { 50, false }, tourneyLoop = { 50, false },
}


-- The decoded state must hold every field the simulation reads, with a type it can
-- hold in play: numbers stay numbers (NaN included); fields that start as undefined
-- may be undefined or numbers; pick and sliderPos may hold their control's string;
-- flags that start false may be booleans or numbers; and the tables the game builds
-- at setup (projects, arrays, strategies, chips) must be tables.
local BECOMES_STRING = { pick = true, sliderPos = true }
local SETUP_TABLES = { "activeProjects", "allStrats", "alphabet", "battles", "choiceANames", "choiceBNames",
    "hStrat", "incomeTracker", "payoffGrid", "qChips", "results", "ships", "stocks", "strats", "vStrat" }
local function validateState(S)
    for key, initial in pairs(Workshop.initial) do
        local v = S[key]
        local ok
        if initial == JSMath.undefined then
            ok = v == JSMath.undefined or type(v) == "number"
        elseif type(initial) == "number" then
            ok = type(v) == "number" or (BECOMES_STRING[key] and type(v) == "string")
        elseif type(initial) == "boolean" then
            ok = type(v) == "boolean" or type(v) == "number"
        else
            ok = type(v) == type(initial)
        end
        expect(ok, "state field " .. key)
    end
    for _, key in ipairs(SETUP_TABLES) do expect(type(S[key]) == "table", "state table " .. key) end
    for _, project in ipairs(Workshop.projects) do
        local entry = S[project.name]
        expect(type(entry) == "table" and type(entry.flag) == "number" and type(entry.uses) == "number"
            and entry.id == project.id, "project " .. project.name)
    end
    for i = 1, 10 do
        local chip = S.qChips[i]
        expect(type(chip) == "table" and type(chip.value) == "number" and type(chip.active) == "number",
            "photonic chip " .. i)
    end
end

-- A game from saved data, drawing from random. Raises "Malformed save: ..." without
-- touching anything when the data does not hold together.
function Save.decode(saved, random, log)
    expect(type(saved) == "table", "not a table")
    expect(saved.schema == Save.SCHEMA, "schema " .. tostring(saved.schema))
    expect(type(saved.nodes) == "table" and type(saved.root) == "number" and type(saved.clock) == "table"
        and type(saved.controls) == "table", "missing parts")
    local tables = {}
    for id, node in pairs(saved.nodes) do
        expect(type(id) == "number" and type(node) == "table", "node " .. tostring(id))
        tables[id] = {}
    end
    expect(tables[saved.root] ~= nil, "root")
    local function value(v)
        if type(v) ~= "table" then return v end
        if v.r ~= nil then
            expect(tables[v.r] ~= nil, "reference " .. tostring(v.r))
            return tables[v.r]
        end
        if v.w ~= nil then return decodeNumber(v.w) end
        if v.u ~= nil then return JSMath.undefined end
        error("Malformed save: value", 0)
    end
    for id, node in pairs(saved.nodes) do
        local t = tables[id]
        for k, x in pairs(node) do t[k] = value(x) end
    end
    local S = tables[saved.root]
    validateState(S)
    S.grid = Battle.newGrid()
    local game = setmetatable({}, Game)
    game.S = S
    expect(type(saved.clock.timers) == "table", "timers")
    local entries = 0
    for k, t in pairs(saved.clock.timers) do
        expect(type(k) == "number" and type(t) == "table", "timer entry")
        entries = entries + 1
    end
    expect(entries == #saved.clock.timers, "timers (not a dense list)")
    local clock = mapClock(saved.clock, value)
    game.clock = Scheduler.restore(clock, log, function(kind, id)
        expect(Workshop.timers[kind] ~= nil, "timer kind " .. tostring(kind))
        return game:timerCallback(kind, id)
    end, SHAPES)
    -- The seven reference intervals never stop: each must be there exactly once.
    local base = { battle = 0, portfolio = 0, stockShop = 0, stockSell = 0, pick = 0, main = 0, slow = 0 }
    for _, t in pairs(game.clock.pending) do
        if base[t.kind] then base[t.kind] = base[t.kind] + 1 end
    end
    for kind, n in pairs(base) do expect(n == 1, "interval " .. kind) end
    -- Controls: every part must be there; nothing is filled in by default.
    local controls = saved.controls
    expect(type(controls.disabled) == "table" and type(controls.projectElements) == "table"
        and type(controls.readouts) == "table" and type(controls.selects) == "table"
        and type(controls.ranges) == "table", "controls")
    game.disabled, game.projectElements, game.readouts = {}, {}, {}
    for _, id in ipairs(Workshop.buttons) do
        expect(type(controls.disabled[id]) == "boolean", "control " .. id)
    end
    for id, v in pairs(controls.disabled) do
        expect(type(id) == "string" and type(v) == "boolean", "control state")
        game.disabled[id] = v
    end
    for id, v in pairs(controls.projectElements) do
        expect(type(id) == "string" and v == true, "project button")
        game.projectElements[id] = v
    end
    for i = 1, 5 do
        expect(type(controls.readouts[i]) == "string", "message " .. i)
        game.readouts[i] = controls.readouts[i]
    end
    game.selects = {}
    for _, id in ipairs({ "investStrat", "stratPicker" }) do
        local select = controls.selects[id]
        expect(type(select) == "table" and type(select.options) == "table" and type(select.value) == "string",
            "select " .. id)
        local options = {}
        for i, o in ipairs(select.options) do
            expect(type(o) == "string", "select option")
            options[i] = o
        end
        game.selects[id] = { options = options, value = select.value }
    end
    game.ranges = {}
    for id, sanitize in pairs(Workshop.rangeControls) do
        local v = controls.ranges[id]
        expect(type(v) == "string" and sanitize(v) == v, "range " .. id)
        game.ranges[id] = { value = v, number = JSMath.toNumber(v), sanitize = sanitize }
    end
    expect(controls.resultsTableDisplay == nil or type(controls.resultsTableDisplay) == "string", "results display")
    game.resultsTableDisplay = controls.resultsTableDisplay
    game.draw = function(site) return random:draw(site, game.clock.now) end
    return game
end

return Save
