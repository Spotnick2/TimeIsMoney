-- Client adapter only; simulation will not call WoW APIs.
TimeIsMoney = TimeIsMoney or {}
local TIM = TimeIsMoney

-- Source evidence, not a measured-runtime claim.
TIM.API_EVIDENCE_BUILD = "1.60.1.70205"
TIM.API = {}

-- Icons (#21): item and spell icons by ID, the item data request, and the clock
-- the pending-request timeout reads.
function TIM.API.GetItemIconByID(itemID) return C_Item.GetItemIconByID(itemID) end
function TIM.API.RequestLoadItemDataByID(itemID) C_Item.RequestLoadItemDataByID(itemID) end
-- An item's quality colour (r, g, b), or nil while its data is not loaded (#84).
function TIM.API.ItemQualityColor(itemID)
    local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
    if not ok or type(quality) ~= "number" then return nil end
    local ok2, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if ok2 and type(r) == "number" then return r, g, b end
end
function TIM.API.GetSpellTexture(spellID) return (C_Spell.GetSpellTexture(spellID)) end
function TIM.API.GetTime() return GetTime() end
-- A sound file by ID on a channel ("Dialog" follows the player's dialog volume).
function TIM.API.PlaySoundFile(fileID, channel) return PlaySoundFile(fileID, channel) end
-- The player's faction ("Alliance", "Horde", or "Neutral"/nil before a choice).
function TIM.API.PlayerFaction() return (UnitFactionGroup("player")) end

function TIM.API.Build()
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build), interface
end
