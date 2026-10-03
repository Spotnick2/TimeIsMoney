-- Client adapter only; simulation will not call WoW APIs.
TimeIsMoney = TimeIsMoney or {}
local TIM = TimeIsMoney

-- Source evidence, not a measured-runtime claim.
TIM.API_EVIDENCE_BUILD = "1.60.1.70205"
TIM.API = {}

function TIM.API.Build()
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build), interface
end
