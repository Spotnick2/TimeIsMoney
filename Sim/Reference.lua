-- The pinned Universal Paperclips edition this simulation ports
-- (docs/reference/paperclips.lock.json). Trace comparison refuses other sources.
local _, ns = ...
ns = ns or {}

ns.Reference = {
    source_sha256 = {
        ["index2.html"] = "526b148a2eabe6543c4964e625fc3bba53984b2c294415fdec939b077478b9cb",
        ["combat.js"] = "c7226d012193c32a00bed53d7cb0119d4d3f91cb556b8e8d1b98dd3375be811a",
        ["globals.js"] = "968abd83c7090f24b6817842b4453b6d24de0e03e06d7ccb5ec4d15bee520919",
        ["projects.js"] = "05034c51809bc0632e8963e671c8e68c68604ca3643da291e0c6fabc86152774",
        ["main.js"] = "ee599076de868869e533490505189ddcb72dcc8748909ceeebe11e789f1b3a0a",
    },
    -- Simulation files in load order.
    files = { "Sim/Reference.lua", "Sim/JSMath.lua", "Sim/Scheduler.lua", "Sim/Battle.lua", "Sim/Workshop.lua",
        "Sim/Investments.lua", "Sim/Strategy.lua", "Sim/Projects.lua", "Sim/CostPow.lua", "Sim/Planet.lua", "Sim/Space.lua" },
}
return ns.Reference
