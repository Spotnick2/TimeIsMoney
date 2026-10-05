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
function TIM.API.GetSpellTexture(spellID) return (C_Spell.GetSpellTexture(spellID)) end
function TIM.API.GetTime() return GetTime() end

function TIM.API.Build()
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build), interface
end
