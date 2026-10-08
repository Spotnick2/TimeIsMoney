-- The minimap button (#78): Gazlowe's round portrait on a glass disc at the
-- minimap's edge. Left click opens or closes the ledger, right click the settings;
-- drag it around the edge (its angle is a setting). Presentation only: it reads the
-- host's state for its tooltip and never touches the simulation.
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton
TimeIsMoney.MinimapButton = MinimapButton

MinimapButton.SIZE = 32
MinimapButton.OFFSET = 10 -- beyond the minimap's radius, as the client's own buttons sit
local Glass = LibStub("LibGlass-1.0"):New()

-- Where the button sits for an angle (degrees, 0 = east, counter-clockwise), on a
-- round minimap (the client offers no shape query on this build).
function MinimapButton.Place(angle)
    local b = MinimapButton.button
    local radius = Minimap:GetWidth() / 2 + MinimapButton.OFFSET
    local a = math.rad(angle)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end

-- The angle from the minimap's centre to the cursor, in degrees (0-360).
function MinimapButton.CursorAngle()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    return math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
end

local function Tip(self)
    local Host, L = ns.Host, ns.L
    local state = (not Host.game and L["minimap.noCompany"]) or (not Host.running and L["minimap.stopped"])
        or (Host.paused and L["minimap.paused"]) or L["minimap.running"]
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Time Is Money", 1, 1, 1)
    GameTooltip:AddLine(state, 0.85, 0.6, 0.4)
    GameTooltip:AddLine(L["minimap.left"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["minimap.right"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function MinimapButton.Build()
    local b = CreateFrame("Button", "TimeIsMoneyMinimapButton", Minimap)
    b:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.glass = Glass.Disc(b, "disc_small")
    -- Gazlowe's 2D portrait (the Director's verified fallback, display 7052); the
    -- coin icon if the portrait call fails.
    b.icon = b.glass.top:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(MinimapButton.SIZE - 8, MinimapButton.SIZE - 8)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    if not pcall(SetPortraitTextureFromCreatureDisplayID, b.icon, ns.Director.DISPLAY) then
        b.icon:SetTexture(MinimapButton.FALLBACK_ICON)
    end
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.Window.ToggleSettings()
        else
            SlashCmdList.TIMEISMONEY("") -- as /tim: the ledger, or why there is none
        end
    end)
    b:SetScript("OnEnter", Tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Dragging moves it around the edge; the angle is saved when it is let go.
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function() MinimapButton.Place(MinimapButton.CursorAngle()) end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        ns.Settings.Set("minimapAngle", MinimapButton.CursorAngle())
        MinimapButton.Place(ns.Settings.values.minimapAngle)
    end)
    MinimapButton.button = b
    MinimapButton.Refresh()
    return b
end
MinimapButton.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Coin_01" -- client-verified (docs/ASSETS.md)

-- Shown or hidden, at the saved angle (settings).
function MinimapButton.Refresh()
    local b = MinimapButton.button
    if not b then return end
    MinimapButton.Place(ns.Settings.values.minimapAngle)
    b:SetShown(ns.Settings.values.minimap)
end

-- /tim minimap and the settings checkbox.
function MinimapButton.Toggle()
    ns.Settings.Set("minimap", not ns.Settings.values.minimap)
    MinimapButton.Refresh()
    return ns.Settings.values.minimap
end
