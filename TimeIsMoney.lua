-- Entry point: load, saves, status, help, the ledger window and the developer
-- commands that drive the simulation directly.
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
    if Host.blocked then
        Print("Saving is off: " .. Host.blocked .. ". TimeIsMoneyDB is left untouched.")
    end
    if not game then
        if not Host.blocked then Print("No company yet: /tim start.") end
        return
    end
    local S, stats = game.S, Host.stats
    local seconds = game.clock.now / 1000
    Print(string.format("%s at %.1f s logical: %s clips, $%s, wire %s, %d steps.",
        Host.running and (Host.paused and "Paused" or "Running") or ("Stopped (" .. tostring(Host.halted) .. ")"), seconds,
        tostring(math.floor(S.clips)), tostring(S.funds), tostring(math.floor(S.wire)), stats.steps))
    if stats.frames > 0 then
        Print(string.format("CPU: %.2f ms per frame on average (%.0f ms per logical second), worst %.1f ms; %.0f ms of time dropped.",
            stats.cpu / stats.frames, stats.steps > 0 and stats.cpu / (stats.steps * Host.STEP / 1000) or 0,
            stats.worst, stats.dropped))
        if stats.snapshotMs then Print(string.format("Last in-memory save: %.1f ms.", stats.snapshotMs)) end
    end
end

local function Slash(message)
    local text = (message or ""):match("^%s*(.-)%s*$")
    local command, rest = text:match("^(%S*)%s*(.*)$")
    command = command:lower()
    local Host = TIM.Host
    if command == "help" then
        TIM.Window.ShowHelp()
        Print("/tim - open or close the ledger. /tim pause - pause or resume the company. /tim minimap - show or hide the minimap button. /tim settings - settings and a new game. /tim help - this help. /tim status - runtime and company. /tim start - a new company when there is none.")
        Print("Developer: /tim click <control> (e.g. btnMakePaperclip), /tim set <control> <value>, /tim icons, /tim model, /tim newgame.")
    elseif command == "" then
        if Host.game then
            TIM.Window.Toggle()
        elseif Host.blocked then
            Print("Saving is off: " .. Host.blocked .. ". TimeIsMoneyDB is left untouched.")
        else
            Print("No company yet: /tim start.")
        end
    elseif command == "status" then
        Status()
    elseif command == "minimap" then
        Print("Minimap button " .. (TIM.MinimapButton.Toggle() and "shown." or "hidden (/tim minimap shows it again)."))
        if TIM.Window.settings and TIM.Window.settings:IsShown() then TIM.Window.FillSettings() end
    elseif command == "pause" then
        local ok, err = Host.setPaused(not Host.paused)
        if ok then
            Print(Host.paused and "Company paused: nothing runs until you resume (/tim pause)." or "Company resumed.")
            TIM.Window.Refresh()
            if TIM.Window.settings and TIM.Window.settings:IsShown() then TIM.Window.FillSettings() end
        else
            Print("pause refused: " .. err)
        end
    elseif command == "icons" then
        TIM.Window.ToggleIcons()
    elseif command == "settings" then
        TIM.Window.ToggleSettings()
    elseif command == "newgame" then
        if Host.blocked then
            Print("Not starting over: " .. Host.blocked .. ". The saved data is kept untouched.")
        elseif not Host.game then
            Print("No company yet: /tim start.")
        else
            TIM.Window.NewGame()
        end
    elseif command == "model" then
        Print("Director model " .. (TIM.Director.ToggleModel() and "on." or "off (portrait)."))
        if TIM.Window.settings and TIM.Window.settings:IsShown() then TIM.Window.FillSettings() end
    elseif command == "start" then
        if Host.blocked then
            Print("Not starting: " .. Host.blocked .. ". The saved data is kept untouched.")
        elseif Host.game then
            Print("Your company is already open. To start over: /tim newgame.")
        else
            Host.start()
            Print("A new company opens its ledger. Time is money, friend!")
            TIM.Window.Toggle()
            -- First use: the help, once (it explains how saving works).
            if not TIM.Settings.values.helpSeen then TIM.Window.ShowHelp() end
        end
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

-- Saves: TimeIsMoneyDB is read once at load and written at logout or /reload, the
-- moment before the client writes SavedVariables to disk. A crash loses what
-- happened since the last write; there is no automatic reload.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        local db = TIM.Host.persist()
        if db then TimeIsMoneyDB = db end
        return
    end
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    TIM.loaded = true
    local state = TIM.Host.loadSaved(TimeIsMoneyDB)
    TIM.Settings.Load(TIM.Host.savedSettings)
    TIM.MinimapButton.Build()
    if state == "restored" then
        Print(string.format("Your company reopens its ledger at %.1f s.", TIM.Host.game.clock.now / 1000))
    elseif state == "blocked" then
        Print("Saving is off: " .. TIM.Host.blocked .. ". TimeIsMoneyDB is left untouched.")
    end
end)
