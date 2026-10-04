-- Logical timer queue with the reference host's ordering rules: callbacks fire by
-- due time, then by a stable queue ordinal; an interval is requeued after its
-- callback unless it was cancelled. Time moves only through advanceTo.
local _, ns = ...
ns = ns or {}

local Scheduler = {}
Scheduler.__index = Scheduler

-- log receives register/cancel/fire events in the runner-neutral trace form; false
-- (the client host) records nothing, so no event tables are created.
function Scheduler.new(log)
    if log == nil then log = {} end
    return setmetatable({ now = 0, nextId = 1, order = 0, pending = {}, log = log }, Scheduler)
end

-- kind names the callback so a saved game can rebuild it (#19); fn is the callback.
function Scheduler:register(fn, delay, repeating, kind)
    if type(fn) ~= "function" then error("Timer callback must be a function", 2) end
    -- A timer without a kind could not be saved: refuse it where it is made.
    if type(kind) ~= "string" or kind == "" then error("Every timer needs a kind (a saved game rebuilds it)", 2) end
    if delay ~= delay or delay < 0 or delay == math.huge then error("Expected a finite nonnegative timer delay", 2) end
    local id = self.nextId
    self.nextId = id + 1
    local timer = { id = id, fn = fn, delay = delay, ["repeat"] = repeating, due = self.now + delay, order = self.order,
        kind = kind }
    self.order = self.order + 1
    self.pending[id] = timer
    if self.log then
        self.log[#self.log + 1] = { action = "register", at = self.now, id = id, delay = delay, ["repeat"] = repeating, due = timer.due }
    end
    return id
end

function Scheduler:clear(id)
    if self.log then
        self.log[#self.log + 1] = { action = "cancel", at = self.now, id = id, existed = self.pending[id] ~= nil }
    end
    self.pending[id] = nil
end

local function before(a, b)
    if a.due ~= b.due then return a.due < b.due end
    return a.order < b.order
end

function Scheduler:next()
    local best
    for _, timer in pairs(self.pending) do
        if not best or before(timer, best) then best = timer end
    end
    return best
end

-- Pending timers in firing order, as {id, delay, repeat, due, order}.
function Scheduler:describe()
    local list = {}
    for _, timer in pairs(self.pending) do list[#list + 1] = timer end
    table.sort(list, before)
    for i, t in ipairs(list) do
        list[i] = { id = t.id, delay = t.delay, ["repeat"] = t["repeat"], due = t.due, order = t.order }
    end
    return list
end

function Scheduler:advanceTo(target, after, maxCallbacks)
    if target ~= target or target < self.now then error("Logical time must move forward", 2) end
    maxCallbacks = maxCallbacks or 100000
    local count = 0
    while true do
        local timer = self:next()
        if not timer or timer.due > target then break end
        count = count + 1
        if count > maxCallbacks then error("Callback budget exceeded", 2) end
        self.now = timer.due
        if not timer["repeat"] then self.pending[timer.id] = nil end
        if self.log then self.log[#self.log + 1] = { action = "fire", at = self.now, id = timer.id } end
        timer.fn()
        if timer["repeat"] and self.pending[timer.id] then
            timer.due = self.now + timer.delay
            timer.order = self.order
            self.order = self.order + 1
        end
        if after then after(timer.id) end
    end
    self.now = target
end

-- Saved timers (#19): plain data, with the kind that rebuilds each callback.
function Scheduler:save()
    local timers = {}
    for _, t in pairs(self.pending) do
        if not t.kind then error("Timer " .. t.id .. " has no kind and cannot be saved", 2) end
        timers[#timers + 1] = { id = t.id, kind = t.kind, delay = t.delay, ["repeat"] = t["repeat"], due = t.due,
            order = t.order }
    end
    table.sort(timers, function(a, b) return a.id < b.id end)
    return { now = self.now, nextId = self.nextId, order = self.order, timers = timers }
end

-- Rebuilds the queue from saved data; build(kind, id) returns each callback.
-- shapes[kind], when given, is {delay, repeat} for kinds with a fixed cadence. The
-- data is checked first: a dense list of well-formed timers with unique integer ids
-- below nextId, nonnegative delays (a repeating timer needs one above 0), due times
-- not in the past and the fixed cadences, so damaged data is refused, not shortened.
local function number(v)
    return type(v) == "number" and not ns.JSMath.isNaN(v) and v ~= math.huge and v ~= -math.huge
end
local function integer(v) return number(v) and v == math.floor(v) end
function Scheduler.restore(saved, log, build, shapes)
    local function expect(cond, what) if not cond then error("Malformed save: timers (" .. what .. ")", 0) end end
    expect(type(saved) == "table" and number(saved.now) and integer(saved.nextId) and integer(saved.order), "counters")
    expect(type(saved.timers) == "table", "list")
    local count, seen = 0, {}
    for _ in pairs(saved.timers) do count = count + 1 end
    expect(count == #saved.timers, "not a dense list")
    for _, t in ipairs(saved.timers) do
        expect(type(t) == "table" and integer(t.id) and type(t.kind) == "string" and number(t.delay)
            and type(t["repeat"]) == "boolean" and number(t.due) and integer(t.order), "entry")
        expect(not seen[t.id] and t.id >= 1 and t.id < saved.nextId and t.due >= saved.now and t.order < saved.order
            and t.delay >= 0 and not (t["repeat"] and t.delay == 0), "entry values")
        local shape = shapes and shapes[t.kind]
        expect(not shape or (t.delay == shape[1] and t["repeat"] == shape[2]), "cadence of " .. t.kind)
        seen[t.id] = true
    end
    local clock = Scheduler.new(log)
    clock.now, clock.nextId, clock.order = saved.now, saved.nextId, saved.order
    for _, t in ipairs(saved.timers) do
        clock.pending[t.id] = { id = t.id, fn = build(t.kind, t.id), delay = t.delay, ["repeat"] = t["repeat"],
            due = t.due, order = t.order, kind = t.kind }
    end
    return clock
end

ns.Scheduler = Scheduler
return Scheduler
