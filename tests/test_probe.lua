-- TimeIsMoneyProbe (#9): offline consistency of the in-game checks and the probe's
-- command and persistence logic under minimal stubs (no rendering claim).
local ns = {}
assert(loadfile("Sim/Reference.lua"))("TimeIsMoneyProbe", ns)
for _, path in ipairs(ns.Reference.files) do assert(loadfile(path))("TimeIsMoneyProbe", ns) end
assert(loadfile("Probe/Vectors.lua"))("TimeIsMoneyProbe", ns)
assert(loadfile("Probe/Checks.lua"))("TimeIsMoneyProbe", ns)
local Checks, Expected = ns.Checks, ns.ProbeVectors

-- The probe TOC loads the simulation in Sim/Reference.lua order, then the probe.
local toc, listed = assert(io.open("Probe/TimeIsMoneyProbe.toc", "r")):read("*a"), {}
for line in toc:gmatch("[^\r\n]+") do
    if line ~= "" and line:sub(1, 1) ~= "#" then listed[#listed + 1] = line end
end
local wanted = {}
for _, path in ipairs(ns.Reference.files) do wanted[#wanted + 1] = path end
for _, name in ipairs({ "Vectors.lua", "Checks.lua", "Probe.lua", "Goblin.lua" }) do wanted[#wanted + 1] = name end
assert(table.concat(listed, ",") == table.concat(wanted, ","), table.concat(listed, ","))
assert(toc:find("## SavedVariables: TimeIsMoneyProbeDB", 1, true))

-- Goblin probe helpers (#10).
assert(Checks.npcFromGUID("Creature-0-4469-0-12-3391-000012AB34") == 3391)
assert(Checks.npcFromGUID("Vehicle-0-1-2-3-28670-0000AB") == 28670)
assert(Checks.npcFromGUID("Player-4469-0ABC1234") == nil and Checks.npcFromGUID("Pet-0-1-2-3-1860-1E2A26") == nil)
local box = Checks.readBox(-0.5, -0.25, -1, 0.5, 0.25, 1)
assert(box.l == 1 and box.w == 0.5 and box.h == 2)
local vbox = Checks.readBox({ x = 0, y = 0, z = 0 }, { x = 1, y = 2, z = 3 })
assert(vbox.l == 1 and vbox.w == 2 and vbox.h == 3)
assert(Checks.readBox(0, 0, 0, 1, 1, 0) == nil and Checks.readBox(nil) == nil)
local scale, offset = Checks.framing({ h = 2, w = 1 }, 100, 100, 40, 0.15, 1, 1)
assert(math.abs(scale * 2 - 2 * 40 * math.tan(0.075)) < 1e-12 and offset == 0, "whole body fills the view")
local wideScale = Checks.framing({ h = 2, w = 3 }, 100, 100, 40, 0.15, 1, 1)
assert(math.abs(wideScale * 3 - 2 * 40 * math.tan(0.075)) < 1e-12, "a wide model fits its width")
local headScale, headOffset = Checks.framing({ h = 2, w = 3 }, 100, 100, 40, 0.15, 0.5, 1)
assert(math.abs(headScale - 2 * scale) < 1e-12 and math.abs(headOffset + 0.5 * headScale) < 1e-12, "top half centred")
local _, scaledOffset = Checks.framing({ h = 2, w = 3 }, 100, 100, 40, 0.15, 0.5, 1, true)
assert(math.abs(scaledOffset + 0.5) < 1e-12, "scaled position: offset in model units")
assert(Checks.compactRanges({ 0, 1, 2, 5, 7, 8 }) == "0-2, 5, 7-8" and Checks.compactRanges({}) == "")

-- FNV-1a reference values.
assert(Checks.fnv1a("") == "811c9dc5" and Checks.fnv1a("a") == "e40c292c" and Checks.fnv1a("foobar") == "bf9cf968")

-- Offline Lua reproduces every vector and the recorded workshop digest.
local counts, failures = Checks.math(Expected.vectors, ns.JSMath)
local total = 0
for name, c in pairs(counts) do
    total = total + c[1]
    assert(c[2] == 0, name .. ": " .. table.concat(failures, "; "))
end
assert(total == #Expected.vectors and total > 1000)
local digest, draws = Checks.workshop(ns)
assert(digest == Expected.workshopDigest and draws == Expected.workshopDraws, digest .. " " .. draws)
local floorDigest, floorDraws = Checks.workshopPriceFloor(ns)
assert(floorDigest == Expected.priceFloorDigest and floorDraws == Expected.priceFloorDraws)
for _, result in ipairs(Checks.environment(ns.JSMath)) do
    assert(type(result.name) == "string" and type(result.ok) == "boolean")
    -- Decimal parsing depends on the C runtime (the old 32-bit build misparses);
    -- every other fact must hold for the simulation.
    if not result.name:find("^tonumber") then assert(result.ok, result.name) end
end

-- Probe.lua and Goblin.lua under stubs: sentinel, commands and isolation from
-- TimeIsMoneyDB. Widgets accept any method; the model ones answer a fake display.
local messages, frames, timers, calls = {}, {}, {}, {}
local function Widget(kind)
    -- Fields read before being set must exist: unknown keys resolve to methods.
    local w = { kind = kind, events = {}, scripts = {}, width = 0, height = 0, shown = 0, streaming = false, mouse = true }
    function w:RegisterEvent(event) self.events[event] = true end
    function w:UnregisterEvent(event) self.events[event] = nil end
    function w:SetScript(name, callback)
        self.scripts[name] = callback
        if name == "OnEvent" then self.onEvent = callback end
    end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:GetWidth() return self.width end
    function w:GetHeight() return self.height end
    function w:CreateTexture() return Widget("Texture") end
    function w:CreateFontString() return Widget("FontString") end
    function w:SetText(text) self.text = text end
    function w:CreateActor()
        local actor = Widget("Actor")
        actor.polls, actor.cleared = 0, 0
        function actor:SetModelByCreatureDisplayID(display) self.display, self.polls = display, 0 return true end
        function actor:ClearModel() self.cleared = self.cleared + 1 end
        function actor:GetActiveBoundingBox()
            self.polls = self.polls + 1
            if self.polls < 3 then error("not loaded") end
            return -0.4, -0.3, -1, 0.4, 0.3, 1
        end
        function actor:SetScale(scale) self.scale = scale end
        function actor:SetPosition(x, y, z) self.z = z end
        function actor:SetAnimation(id) self.anim = id end
        function actor:GetModelFileID() return 12345 end
        return actor
    end
    -- The lookup model: the unit and the template can answer different looks.
    function w:ClearModel() self.shown, self.streaming = 0, false end
    function w:SetUnit() self.shown = 7002 end
    -- SetCreature streams: it answers on the second poll.
    function w:SetCreature(npc) self.shown, self.streaming = 0, npc == 3391 and 7001 or 7100 end
    function w:SetDisplayInfo(display) self.shown = display end
    function w:GetDisplayInfo()
        if self.streaming then self.shown, self.streaming = self.streaming, false return 0 end
        return self.shown or 0
    end
    function w:HasAnimation(id)
        if id > 1865 then error("Usage: local hasAnimation = self:HasAnimation(anim)") end
        return id == 0 or id == 1 or id == 60 or id == 69
    end
    function w:IsMouseEnabled() return self.mouse end
    function w:EnableMouse(on) self.mouse = on end
    function w:GetFrameLevel() return 5 end
    function w:GetFrameStrata() return "DIALOG" end
    return setmetatable(w, { __index = function(_, key)
        return function(...) calls[#calls + 1] = kind .. ":" .. key end
    end })
end
local env = {
    print = function(message) messages[#messages + 1] = message end,
    GetBuildInfo = function() return "1.60.1", "70338", "Oct 9 2026", 16001 end,
    SlashCmdList = {}, string = string, math = math, table = table, pairs = pairs, ipairs = ipairs,
    tostring = tostring, pcall = pcall, type = type, _VERSION = _VERSION,
    date = function() return "12:00:00" end,
    debugprofilestop = function() return 0 end,
    TimeIsMoneyProbeDB = { loadCount = 2, marker = "before" },
    CreateFrame = function(kind)
        local frame = Widget(kind)
        frames[#frames + 1] = frame
        return frame
    end,
    UIParent = Widget("UIParent"), unpack = unpack, select = select, tonumber = tonumber,
    GetTime = function() return 100 end,
    C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end },
    UnitGUID = function() return "Creature-0-4469-0-12-3391-000012AB34" end,
    UnitName = function() return "Gazlowe" end,
    UnitIsPlayer = function() return false end,
    UnitRace = function() return "Goblin", "Goblin", 9 end,
    UnitCreatureType = function() return "Humanoid", 7 end,
    GetRealZoneText = function() return "Ratchet" end,
    SetPortraitTextureFromCreatureDisplayID = function(texture, display) texture.portrait = display end,
}
local function pump()
    while #timers > 0 do table.remove(timers, 1)() end
end
setmetatable(env, { __index = function(_, key)
    if key == "TimeIsMoneyDB" then return nil end
    error("Unvalidated global: " .. tostring(key), 2)
end })
for _, file in ipairs({ "Probe/Probe.lua", "Probe/Goblin.lua" }) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)
    chunk("TimeIsMoneyProbe", ns)
end
local function last() return messages[#messages] end
frames[1].onEvent(frames[1], "ADDON_LOADED", "Another", false)
assert(env.TimeIsMoneyProbeDB.loadCount == 2, "other addons are ignored")
frames[1].onEvent(frames[1], "ADDON_LOADED", "TimeIsMoneyProbe", false)
assert(env.TimeIsMoneyProbeDB.loadCount == 3 and last():find("previous loadCount=2", 1, true))
local slash = env.SlashCmdList.TIMEISMONEYPROBE
slash("status")
assert(messages[#messages - 2]:find("previous loadCount=2 %(nil = the file was not read%), now 3"))
assert(messages[#messages - 1]:find("marker at load=before", 1, true))
assert(last():find("TimeIsMoneyDB is untouched", 1, true))
slash("save hello")
assert(env.TimeIsMoneyProbeDB.marker == "hello @12:00:00" and env.TimeIsMoneyProbeDB.markerBuild == "1.60.1.70338")
slash("math")
assert(last():find("math: exact", 1, true), last())
slash("sim")
assert(messages[#messages - 1]:find("sim: matches offline Lua", 1, true), messages[#messages - 1])
assert(last():find("sim zero price: digest .* matches offline Lua"), last())
slash("bogus")
assert(messages[#messages - 1]:find("/timprobe env", 1, true) and last():find("goblins:", 1, true))

-- Goblin model probe (#10): target -> npc -> display, recorded with provenance;
-- the box poll fits both panes; a closed window drops late callbacks.
slash("target")
pump()
assert(messages[#messages - 1]:find("target Gazlowe: npc 3391, unit display 7002, template display 7001 %(Humanoid, Ratchet%); recorded"), messages[#messages - 1])
assert(last():find("goblin 7002: box after", 1, true), last())
local recorded = env.TimeIsMoneyProbeDB.goblins[1]
assert(recorded.npc == 3391 and recorded.display == 7002 and recorded.unitDisplay == 7002 and recorded.templateDisplay == 7001)
assert(recorded.build == "1.60.1.70338" and recorded.zone == "Ratchet")
local window = frames[2]
assert(window.body.actor.display == 7002 and window.strip.actor.display == 7002 and window.portrait.portrait == 7002)
assert(window.lookup.mouse == false, "the lookup model never takes the mouse")
assert(window.strip.actor.scale > window.body.actor.scale and window.strip.actor.z < 0 and window.body.actor.z == 0)
assert(window.body.mouse == false and window.strip.mouse == false, "scenes never take the mouse")
assert(window.body.actor.cleared == 1 and window.strip.actor.cleared == 1, "the previous model is cleared first")
slash("anims")
pump()
assert(messages[#messages - 1]:find("anims for display 7002: 4 IDs (HasAnimation rejects 1866 and up): 0-1, 60, 69", 1, true), messages[#messages - 1])
slash("anim next") slash("anim Next") slash("ANIM next")
assert(window.body.actor.anim == 60 and last():find("anim 60 (3 of 4)", 1, true), last())
slash("posmode world")
assert(window.strip.actor.z < -1 and last():find("posmode world", 1, true))
slash("posmode scaled")
assert(window.strip.actor.z > -1)
slash("crop 0.3 0.1")
assert(last() == "|cffd9a066TIM probe|r: crop 0.30, nudge 0.10")
slash("goblin 8000")
assert(window.body.actor.scale == 1 and window.body.actor.z == 0, "no fit carried over to a new display")
slash("crop 0.4")
assert(last():find("no box yet", 1, true), last())
slash("close")
pump()
assert(last():find("closed", 1, true), "a late box answer after close prints nothing")
-- Overlapping lookups: only the newer one records.
slash("npc 4444")
slash("npc 3391")
pump()
local goblins = env.TimeIsMoneyProbeDB.goblins
assert(#goblins == 2 and goblins[2].npc == 3391 and goblins[2].display == 7001, "the older lookup was cancelled")
-- A direct display wins over an NPC lookup still streaming (Codex).
slash("npc 3391")
slash("goblin 8000")
pump()
assert(window.body.actor.display == 8000 and #env.TimeIsMoneyProbeDB.goblins == 2, "the pending lookup was cancelled")
-- A lookup replaced while the scan waits for the model cancels the scan (Codex).
local hasAnimation = window.lookup.HasAnimation
local ready = false
window.lookup.HasAnimation = function(self, id) if id == 0 and not ready then return false end return hasAnimation(self, id) end
slash("anims")
slash("npc 3391")
ready = true
pump()
local scanned = false
for _, message in ipairs(messages) do if message:find("anims for display 8000", 1, true) then scanned = true end end
assert(not scanned, "no animation list for a replaced lookup")
window.lookup.HasAnimation = hasAnimation
-- anims refuses to scan a lookup that holds another display.
window.lookup.SetDisplayInfo = function(self) self.shown = 9999 end
slash("goblin 7001")
pump()
slash("anims")
pump()
assert(last():find("reports display 9999, not 7001; not scanned", 1, true), last())
env.UnitIsPlayer = function() return true end
slash("target")
assert(last():find("is a player %(Goblin%)"), last())
assert(rawget(env, "TimeIsMoneyDB") == nil)
print("probe: vectors, workshop digest, TOC order, sentinel and commands passed")
