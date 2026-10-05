-- Presentation assets (#21): the plan's 14 item identities (Appendix B) and an icon
-- family for every project. Item and spell IDs are database-listed (the plan's
-- research and the supplied Forever recipe snapshot, 2026-09-30); each still needs
-- its in-client check (/tim icons), and every lookup has a fallback. An item ID is
-- not a texture: icons resolve through the client, item data may load later.
local _, ns = ...

local Assets = {}
ns.Assets = Assets

local WOWHEAD = "https://www.wowhead.com/forever/"
Assets.FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The question mark's file ID: an item the client does not know may come back with
-- it rather than nil; it counts as missing, never as resolved.
Assets.QUESTION_MARK_ID = 134400
-- How long a requested item may stay pending before it falls back (seconds). The
-- client measurement (forever-api-notes, #9) saw no item-load event for 10 s while
-- GetItemIconByID already answered, so the event is never waited on.
Assets.PENDING_TIMEOUT = 10
local API = TimeIsMoney.API

-- The 14 identities: role, Time Is Money name, Forever item.
Assets.IDENTITIES = {
    { key = "clips", name = "Handfuls of Copper Bolts", item = 4359 },
    { key = "wire", name = "Copper Bars", item = 2840 },
    { key = "autoClippers", name = "Whirring Bronze Gizmos", item = 4375 },
    { key = "megaClippers", name = "Thorium Widgets", item = 15994 },
    { key = "processors", name = "Copper Modulators", item = 4363 },
    { key = "memory", name = "White Punch Cards", item = 9279 },
    { key = "chips", name = "Arcane Crystals", item = 12363 },
    { key = "harvesters", name = "Compact Harvest Reapers", item = 4391 },
    { key = "wireDrones", name = "Delicate Arcanite Converters", item = 16006 },
    { key = "farms", name = "Gold Power Cores", item = 10558 },
    { key = "batteries", name = "9-60 Battery Packs", item = 274048 },
    { key = "probes", name = "Arcanite Dragonlings", item = 16022 },
    { key = "mindControl", name = "Gnomish Mind Control Cap", item = 10726 },
    { key = "expansion", name = "Dimensional Ripper - Everlook", item = 18984 },
}
Assets.identity = {}
for _, entry in ipairs(Assets.IDENTITIES) do Assets.identity[entry.key] = entry end

-- Icon families: a research family shares one icon (plan Appendix B). Sources are
-- an identity, another database-listed item (recipe snapshot: crafted item IDs), a
-- profession spell, or a texture path with no database entry (checked in client).
Assets.FAMILIES = {
    gizmo = { identity = "autoClippers" },
    widget = { identity = "megaClippers" },
    copper = { identity = "wire" },
    bolts = { identity = "clips" },
    modulator = { identity = "processors" },
    punchCard = { identity = "memory" },
    crystal = { identity = "chips" },
    reaper = { identity = "harvesters" },
    converter = { identity = "wireDrones" },
    power = { identity = "farms" },
    dragonling = { identity = "probes" },
    mindControl = { identity = "mindControl" },
    expansion = { identity = "expansion" },
    tinkering = { name = "Arclight Spanner", item = 6219 },
    writing = { name = "Goblin Rocket Fuel Recipe", item = 10644 },
    correspondence = { name = "Schematic: Gnomish Universal Remote", item = 7560 },
    precision = { name = "Gyrochronatom", item = 4389 },
    foresight = { name = "Ornate Spyglass", item = 5507 },
    negotiation = { name = "Gnomish Universal Remote", item = 7506 },
    automation = { name = "Bronze Tube", item = 4371 },
    fleet = { name = "Goblin Jumper Cables XL", item = 18587 },
    speed = { name = "Goblin Rocket Fuel", item = 9061 },
    network = { name = "Truesilver Transformer", item = 18631 },
    hull = { name = "Mithril Casing", item = 10561 },
    enforcement = { name = "Goblin Mortar", item = 10577 },
    weather = { name = "World Enlarger", item = 18660 },
    foundry = { name = "Blacksmithing", spell = 2018 },
    remedy = { name = "Alchemy", spell = 2259 },
    money = { name = "Coins", texture = "Interface\\Icons\\INV_Misc_Coin_01" },
}

-- Every project's family, by reference ID (Appendix A's purposes).
local FAMILY_OF = {
    gizmo = { 1, 4, 5 }, correspondence = { 2, 13, 140, 141, 142, 143, 144, 145, 146, 147, 148 },
    tinkering = { 3 }, writing = { 6, 11, 12, 14, 121, 133, 134, 218 }, copper = { 7, 8, 9, 10, "10b" },
    precision = { 15, 16, 17, 217 }, bolts = { 18 }, foresight = { 19, 27, 119 },
    negotiation = { 20, 60, 61, 62, 63, 64, 65, 66, 118, 128, 213 }, money = { 21, 37, 38, 40, "40b", 42 },
    widget = { 22, 23, 24, 25 }, automation = { 26 }, mindControl = { 34, 35, 70 },
    remedy = { 28, 31 }, enforcement = { 29, 131 }, weather = { 30 }, converter = { 41, 44 },
    reaper = { 43 }, foundry = { 45, 100, 101, 102, 212 }, expansion = { 46, 200, 201 },
    crystal = { 50, 51, 214 }, fleet = { 110, 111, 112 }, speed = { 120 }, power = { 125, 127 },
    network = { 126, 130, 132, 211 }, hull = { 129 }, punchCard = { 135, 216 }, dragonling = { 210 },
    modulator = { 215, 219 },
}
Assets.PROJECT_FAMILY = {}
for family, ids in pairs(FAMILY_OF) do
    for _, id in ipairs(ids) do Assets.PROJECT_FAMILY["project" .. id] = family end
end

-- Where an icon comes from: { kind = "item"|"spell"|"texture", id|path, name, url }.
-- Built once per identity and family (the window asks on every redraw).
local identitySources, familySources = {}, {}
function Assets.IdentitySource(key)
    local source = identitySources[key]
    if not source then
        local entry = Assets.identity[key]
        source = { kind = "item", id = entry.item, name = entry.name, url = WOWHEAD .. "item=" .. entry.item }
        identitySources[key] = source
    end
    return source
end
local function buildSource(family)
    local f = Assets.FAMILIES[family]
    if f.identity then
        return Assets.IdentitySource(f.identity)
    elseif f.item then
        return { kind = "item", id = f.item, name = f.name, url = WOWHEAD .. "item=" .. f.item }
    elseif f.spell then
        return { kind = "spell", id = f.spell, name = f.name, url = WOWHEAD .. "spell=" .. f.spell }
    end
    return { kind = "texture", path = f.texture, name = f.name }
end
function Assets.Source(family)
    local source = familySources[family]
    if not source then
        source = buildSource(family)
        familySources[family] = source
    end
    return source
end

-- Resolution, never waiting on an event:
-- - Items: GetItemIconByID, polled on each lookup. A nil answer requests the item's
--   data once; the item stays pending until the icon answers or PENDING_TIMEOUT
--   passes, then falls back for good. ITEM_DATA_LOAD_RESULT only shortens the wait
--   (a failure falls back at once). The question mark's file ID counts as missing.
-- - Spells: GetSpellTexture by ID (always local).
-- - Texture paths: used as given; only the client can show whether they exist.
-- Final answers are kept per source, so redraws do not look up again.
Assets.state = {}   -- [item id] = { requested = time } | "failed"
Assets.cache = {}   -- [source] = { icon, status } once resolved or fallen back
Assets.onLoaded = nil

local function final(source, icon, status)
    Assets.cache[source] = { icon, status }
    return icon, status
end

function Assets.IconForSource(source)
    local known = Assets.cache[source]
    if known then return known[1], known[2] end
    if source.kind == "texture" then return final(source, source.path, "path") end
    if source.kind == "spell" then
        local icon = API.GetSpellTexture(source.id)
        if icon and icon ~= Assets.QUESTION_MARK_ID then return final(source, icon, "resolved") end
        return final(source, Assets.FALLBACK, "fallback")
    end
    local icon = API.GetItemIconByID(source.id)
    if icon == Assets.QUESTION_MARK_ID then return final(source, Assets.FALLBACK, "fallback") end
    if icon then return final(source, icon, "resolved") end
    local state = Assets.state[source.id]
    if state == "failed" then return final(source, Assets.FALLBACK, "fallback") end
    if state == nil then
        Assets.state[source.id] = { requested = API.GetTime() }
        API.RequestLoadItemDataByID(source.id)
    elseif API.GetTime() - state.requested >= Assets.PENDING_TIMEOUT then
        Assets.state[source.id] = "failed"
        return final(source, Assets.FALLBACK, "fallback")
    end
    return Assets.FALLBACK, "pending"
end

function Assets.Icon(family)
    return Assets.IconForSource(Assets.Source(family))
end

function Assets.ProjectIcon(projectName)
    local family = Assets.PROJECT_FAMILY[projectName]
    if not family then return Assets.FALLBACK, "fallback" end
    return Assets.Icon(family)
end

function Assets.IdentityIcon(key)
    return Assets.IconForSource(Assets.IdentitySource(key))
end

-- ITEM_DATA_LOAD_RESULT: a requested item loaded (look again) or failed (fallback).
local listener = CreateFrame("Frame")
listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
listener:SetScript("OnEvent", function(_, _, itemID, success)
    if type(Assets.state[itemID]) ~= "table" then return end
    if success and API.GetItemIconByID(itemID) then
        Assets.state[itemID] = nil
    else
        Assets.state[itemID] = "failed"
    end
    if Assets.onLoaded then Assets.onLoaded(itemID) end
end)
Assets.listener = listener
