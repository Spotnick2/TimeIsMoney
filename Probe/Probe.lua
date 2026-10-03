-- TimeIsMoneyProbe (issue #9): developer measurements in the Forever client.
-- Commands: /timprobe env | math | sim | nan | icons | save <text> | status | all.
-- Developer-only; not part of the TimeIsMoney addon or its package. It never
-- reads or writes TimeIsMoneyDB.
local ADDON, ns = ...
local Checks, JSMath, Expected = ns.Checks, ns.JSMath, ns.ProbeVectors

local function Print(message)
    print("|cffd9a066TIM probe|r: " .. message)
end

local function Build()
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build), tostring(interface)
end

local function Env()
    local build, interface = Build()
    Print("client " .. build .. ", interface " .. interface .. ", API evidence 1.60.1.70170")
    local failed = 0
    for _, result in ipairs(Checks.environment(JSMath)) do
        if not result.ok then failed = failed + 1 end
        Print((result.ok and "ok   " or "FAIL ") .. result.name .. (result.observed ~= "" and (": " .. result.observed) or ""))
    end
    Print("env: " .. (failed == 0 and "all checks passed" or (failed .. " check(s) FAILED")))
end

local function Math()
    local started = debugprofilestop()
    local ran, counts, failures = pcall(Checks.math, Expected.vectors, JSMath)
    local elapsed = debugprofilestop() - started
    if not ran then
        Print("math: ERROR " .. tostring(counts))
        return
    end
    local total, bad = 0, 0
    for name, c in pairs(counts) do
        total, bad = total + c[1], bad + c[2]
        Print(string.format("math %s: %d cases, %d mismatches", name, c[1], c[2]))
    end
    for _, failure in ipairs(failures) do Print("  FAIL " .. failure) end
    Print(string.format("math: %s (%d cases, %.0f ms)", bad == 0 and "exact" or "MISMATCHES", total, elapsed))
end

-- Prints the state fields whose digests differ from offline Lua.
local function ReportFields(label, fields, expected)
    local names = {}
    for name in pairs(expected) do
        if fields[name] ~= expected[name] then names[#names + 1] = name end
    end
    for name in pairs(fields) do
        if expected[name] == nil then names[#names + 1] = name end
    end
    table.sort(names)
    if #names > 0 then Print(label .. " differing fields: " .. table.concat(names, ", ", 1, math.min(#names, 20))) end
end

local function Sim()
    local started = debugprofilestop()
    local ok, digest, draws, ticks, fields = pcall(Checks.workshop, ns)
    local elapsed = debugprofilestop() - started
    if not ok then
        Print("sim: ERROR " .. tostring(digest))
        return
    end
    local match = digest == Expected.workshopDigest and draws == Expected.workshopDraws
    Print(string.format("sim: digest %s, %d draws, %d ticks, %.0f ms", digest, draws, ticks, elapsed))
    Print("sim: " .. (match and "matches offline Lua" or ("DIFFERS from offline Lua " .. Expected.workshopDigest)))
    ReportFields("sim", fields, Expected.workshopFields)
    local ranFloor, floorDigest, floorDraws, floorFields = pcall(Checks.workshopPriceFloor, ns)
    if not ranFloor then
        Print("sim zero price: ERROR " .. tostring(floorDigest))
    elseif floorDigest == Expected.priceFloorDigest and floorDraws == Expected.priceFloorDraws then
        Print("sim zero price: digest " .. floorDigest .. " matches offline Lua")
    else
        Print("sim zero price: digest " .. floorDigest .. " DIFFERS from offline Lua " .. Expected.priceFloorDigest)
        ReportFields("sim zero price", floorFields, Expected.priceFloorFields)
    end
end

-- Icons ---------------------------------------------------------------------

local ITEMS = {
    { id = 6948, label = "Hearthstone (established item)" },
    { id = 274048, label = "Forever battery" },
}
local SPELL = { id = 2259, label = "Alchemy (profession spell)" }
local ITEM_TIMEOUT = 10 -- seconds per item request

local frame, rows, requestToken = nil, {}, 0

local function Row(index)
    if rows[index] then return rows[index] end
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -12 - (index - 1) * 44)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    text:SetJustifyH("LEFT")
    rows[index] = { icon = icon, text = text }
    return rows[index]
end

local function ShowRow(index, fileID, line)
    local row = Row(index)
    row.icon:SetTexture(fileID or 134400) -- question mark when absent
    row.text:SetText(line)
    Print(line .. " (icon " .. tostring(fileID) .. ")")
end

local function ShowItem(index, item, token)
    local started = GetTime()
    local function Report(loaded)
        if token ~= requestToken then return end -- a newer request owns the rows
        local name = C_Item.GetItemNameByID(item.id)
        local fileID = C_Item.GetItemIconByID(item.id)
        local state = loaded and string.format("loaded in %.1fs", GetTime() - started)
            or ("not loaded after " .. ITEM_TIMEOUT .. "s")
        ShowRow(index, fileID, string.format("%s %d: %s [%s]", item.label, item.id, tostring(name), state))
    end
    if C_Item.IsItemDataCachedByID(item.id) then
        Report(true)
        return
    end
    local waiter = CreateFrame("Frame")
    local done = false
    waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    waiter:SetScript("OnEvent", function(self, _, itemID, success)
        if itemID ~= item.id or done then return end
        done = true
        self:UnregisterAllEvents()
        Report(success)
    end)
    C_Item.RequestLoadItemDataByID(item.id)
    C_Timer.After(ITEM_TIMEOUT, function()
        if done then return end
        done = true
        waiter:UnregisterAllEvents()
        Report(false)
    end)
end

local function Icons()
    if not frame then
        frame = CreateFrame("Frame", "TimeIsMoneyProbeFrame", UIParent)
        frame:SetSize(420, 150)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.75)
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", function(self) self:Hide() end)
    end
    frame:Show()
    requestToken = requestToken + 1
    for index, item in ipairs(ITEMS) do ShowItem(index, item, requestToken) end
    local info = C_Spell.GetSpellInfo(SPELL.id)
    local fileID = C_Spell.GetSpellTexture(SPELL.id)
    ShowRow(#ITEMS + 1, fileID, string.format("%s %d: %s", SPELL.label, SPELL.id, tostring(info and info.name)))
    Print("icons: frame shown (click it to close); take a screenshot")
end

-- Persistence ---------------------------------------------------------------

-- Read at ADDON_LOADED: SavedVariables load after the addon's files, so a
-- file-scope read would always look empty.
local previousLoad, previousMarker

local function Status()
    local db = TimeIsMoneyProbeDB
    Print("save: previous loadCount=" .. tostring(previousLoad) .. " (nil = the file was not read), now "
        .. tostring(db and db.loadCount))
    Print("save: marker at load=" .. tostring(previousMarker) .. ", marker now=" .. tostring(db and db.marker)
        .. ", last saved by " .. tostring(db and db.markerBuild))
    Print("save: TimeIsMoneyDB is " .. (TimeIsMoneyDB == nil and "untouched (nil)" or "present"))
end

local function Save(text)
    TimeIsMoneyProbeDB.marker = (text ~= "" and text or "marker") .. " @" .. date("%H:%M:%S")
    TimeIsMoneyProbeDB.markerBuild = (Build())
    Print("save: marker set to '" .. TimeIsMoneyProbeDB.marker .. "'; /reload or log out writes it to disk")
end

local function Slash(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "env" then Env()
    elseif command == "math" then Math()
    elseif command == "sim" then Sim()
    elseif command == "nan" then
        for _, line in ipairs(Checks.nan()) do Print("nan: " .. line) end
    elseif command == "icons" then Icons()
    elseif command == "save" then Save(rest)
    elseif command == "status" then Status()
    elseif command == "all" then Env(); Math(); Sim(); Status()
    else
        Print("/timprobe env | math | sim | nan | icons | save <text> | status | all")
    end
end

SLASH_TIMEISMONEYPROBE1 = "/timprobe"
SlashCmdList.TIMEISMONEYPROBE = Slash

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    previousLoad = TimeIsMoneyProbeDB and TimeIsMoneyProbeDB.loadCount
    previousMarker = TimeIsMoneyProbeDB and TimeIsMoneyProbeDB.marker
    TimeIsMoneyProbeDB = TimeIsMoneyProbeDB or {}
    TimeIsMoneyProbeDB.loadCount = (previousLoad or 0) + 1
    Print("loaded; previous loadCount=" .. tostring(previousLoad) .. ". /timprobe for commands.")
end)
