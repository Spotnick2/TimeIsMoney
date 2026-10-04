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

function Scheduler:register(fn, delay, repeating)
    if type(fn) ~= "function" then error("Timer callback must be a function", 2) end
    if delay ~= delay or delay < 0 or delay == math.huge then error("Expected a finite nonnegative timer delay", 2) end
    local id = self.nextId
    self.nextId = id + 1
    local timer = { id = id, fn = fn, delay = delay, ["repeat"] = repeating, due = self.now + delay, order = self.order }
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

ns.Scheduler = Scheduler
return Scheduler
