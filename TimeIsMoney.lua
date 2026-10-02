-- Initialization only; gameplay and save schema belong to later issues.
local ADDON = ...
TimeIsMoney = TimeIsMoney or {}
local TIM = TimeIsMoney

local function Print(message)
    print("|cffd9a066Time Is Money|r: " .. message)
end

local function Slash(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "help" then
        Print("/tim (also /timeismoney) - project status. /tim status - runtime details.")
    elseif command == "status" then
        local build, interface = TIM.API.Build()
        Print("Scaffold only; gameplay is not implemented. Client " .. build
            .. ", Interface " .. tostring(interface) .. ", " .. _VERSION
            .. ". API evidence: " .. TIM.API_EVIDENCE_BUILD .. ".")
    else
        Print("Not playable yet. Time is money, friend! /tim help")
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
    -- Never create/replace TimeIsMoneyDB before its schema is designed.
end)
