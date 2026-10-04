-- Entry point: load, status, help and the developer commands that drive the
-- simulation until the ledger window exists (#20). Saves are #19.
local ADDON = ...
TimeIsMoney = TimeIsMoney or {}
local TIM = TimeIsMoney

local function Print(message)
    print("|cffd9a066Time Is Money|r: " .. message)
end

local function Status()
    local build, interface = TIM.API.Build()
    Print("Client " .. build .. ", Interface " .. tostring(interface) .. ", " .. _VERSION
        .. ". API evidence: " .. TIM.API_EVIDENCE_BUILD .. ".")
    local Host = TIM.Host
    local game = Host.game
    if not game then
        Print("No company yet: /tim start. Progress is not saved yet (#19).")
        return
    end
    local S, stats = game.S, Host.stats
    local seconds = game.clock.now / 1000
    Print(string.format("%s at %.1f s logical: %s clips, $%s, wire %s, %d steps.",
        Host.running and "Running" or ("Stopped (" .. tostring(Host.halted) .. ")"), seconds,
        tostring(math.floor(S.clips)), tostring(S.funds), tostring(math.floor(S.wire)), stats.steps))
    if stats.frames > 0 then
        Print(string.format("CPU: %.2f ms per frame on average, worst %.1f ms; %.0f ms of time dropped.",
            stats.cpu / stats.frames, stats.worst, stats.dropped))
    end
end

local function Slash(message)
    local text = (message or ""):match("^%s*(.-)%s*$")
    local command, rest = text:match("^(%S*)%s*(.*)$")
    command = command:lower()
    local Host = TIM.Host
    if command == "help" then
        Print("/tim status - runtime and company. /tim start - a new company (not saved yet).")
        Print("Developer: /tim click <control> (e.g. btnMakePaperclip), /tim set <control> <value>.")
    elseif command == "status" or command == "" then
        Status()
    elseif command == "start" then
        Host.start()
        Print("A new company opens its ledger. Time is money, friend!")
    elseif command == "click" then
        local ok, err = Host.click(rest)
        if not ok then Print("click refused: " .. err) end
    elseif command == "set" then
        local id, value = rest:match("^(%S+)%s+(.+)$")
        if not id then Print("usage: /tim set <control> <value>") return end
        local ok, err = Host.setValue(id, value)
        if not ok then Print("set refused: " .. err) end
    else
        Print("Unknown command. /tim help")
    end
end

SLASH_TIMEISMONEY1 = "/timeismoney"
SLASH_TIMEISMONEY2 = "/tim"
SlashCmdList.TIMEISMONEY = Slash

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    TIM.loaded = true
    -- Never create/replace TimeIsMoneyDB before its schema is designed (#19).
end)
