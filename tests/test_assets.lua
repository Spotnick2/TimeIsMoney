-- Presentation assets (#21): the 14 identities, an icon for every project, and the
-- resolution path (nil icons, asynchronous loads, bounded retries, fallbacks).
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local Assets, Window = ns.Assets, ns.Window

-- The identities are exactly plan Appendix B's table: role order, names and IDs.
local plan = assert(io.open("docs/plan/Time-Is-Money-Original-Plan.md", "rb")):read("*a")
local appendix = plan:match("## Appendix B.-\n(.-)\n## ") or plan:match("## Appendix B(.*)$")
local planIds = {}
for id in appendix:gmatch("|%s*(%d+)%s*|\r?\n") do planIds[#planIds + 1] = tonumber(id) end
assert(#planIds == 14 and #Assets.IDENTITIES == 14, "14 identities: " .. #planIds)
for i, entry in ipairs(Assets.IDENTITIES) do
    assert(entry.item == planIds[i], entry.name .. " is item " .. planIds[i] .. " in the plan")
end

-- Every one of the 96 projects has an icon family, and every family a source.
local count = 0
for _, project in ipairs(ns.Workshop.projects) do
    count = count + 1
    local family = Assets.PROJECT_FAMILY[project.name]
    assert(family and Assets.FAMILIES[family], project.name .. " has no icon family")
end
assert(count == 96)
for family in pairs(Assets.FAMILIES) do
    local source = Assets.Source(family)
    assert(source.kind == "item" or source.kind == "spell" or source.kind == "texture", family)
    assert(source.name, family .. " has a name")
end

-- Resolution: a known item resolves; an unknown one is requested once (the listener
-- is already registered), stays on the fallback while pending, then resolves after a
-- successful load, or falls back for good after a failed one.
captured.itemIcons[4359] = 134068
assert(select(2, Assets.IdentityIcon("clips")) == "resolved" and Assets.IdentityIcon("clips") == 134068)
local icon, status = Assets.IdentityIcon("batteries")
assert(icon == Assets.FALLBACK and status == "pending" and captured.requested[1] == 274048)
Assets.IdentityIcon("batteries")
assert(#captured.requested == 1, "requested once, not on every redraw")
local loaded
Assets.onLoaded = function(id) loaded = id end
captured.itemIcons[274048] = 999
captured:ItemLoaded(274048, true)
assert(loaded == 274048 and Assets.IdentityIcon("batteries") == 999)
-- A failed load: the fallback, and no further requests.
icon, status = Assets.IdentityIcon("probes")
captured:ItemLoaded(16022, false)
icon, status = Assets.IdentityIcon("probes")
assert(icon == Assets.FALLBACK and status == "fallback" and #captured.requested == 2)
-- A load that succeeds but still has no icon counts as failed (one retry only).
Assets.IdentityIcon("expansion")
captured:ItemLoaded(18984, true)
assert(select(2, Assets.IdentityIcon("expansion")) == "fallback")
-- An unrelated item's load result is ignored.
captured:ItemLoaded(1, true)
-- Spells resolve by ID; texture paths are used as given.
assert(select(2, Assets.Icon("foundry")) == "resolved" and Assets.Icon("foundry") == 100000 + 2018)
assert(Assets.Icon("money") == "Interface\\Icons\\INV_Misc_Coin_01" and select(2, Assets.Icon("money")) == "path")

-- In the window: identity icons on their rows, family icons on project buttons.
Assets.onLoaded = nil
env.SlashCmdList.TIMEISMONEY("start")
local game = ns.Host.game
game.S.projectsFlag = 1
game.S.funds = 100
ns.Host.update(0.02)
assert(ns.Host.click("btnMakeClipper"))
ns.Host.update(0.05)
Window.Refresh()
local boltIcon
for _, t in ipairs(captured.textures) do
    if t.texture == 134068 and h.visible(t) then boltIcon = t end
end
assert(boltIcon, "the bolts row shows its item icon")
local project = assert(h.button("projectButton1"))
assert(project.icon.texture == Assets.ProjectIcon("project1"), "Precision Dies shows the gizmo family's icon")
-- A late item load redraws the window.
assert(type(Assets.onLoaded) == "function")

-- /tim icons: every identity and family listed with its status.
env.SlashCmdList.TIMEISMONEY("icons")
assert(Window.icons and Window.icons:IsShown())
local families = 0
for _, f in pairs(Assets.FAMILIES) do if not f.identity then families = families + 1 end end
local cells = 0
for _, cell in ipairs(Window.icons.cells) do if cell.shown ~= false then cells = cells + 1 end end
assert(cells == 14 + families, cells .. " entries")
assert(h.shownText("Handfuls of Copper Bolts") and h.shownText("Blacksmithing") and h.shownText("fallback"))
-- Hovering an entry gives its source and the projects that use it.
local lines = {}
env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
for _, cell in ipairs(Window.icons.cells) do
    if cell.entry.title == "Blacksmithing" then cell.scripts.OnEnter(cell) end
end
local text = table.concat(lines, "\n")
assert(text:find("spell 2018", 1, true) and text:find("Bolt Foundries", 1, true), text)

print((libGlass and "assets (real LibGlass)" or "assets (LibGlass stand-in)")
    .. ": plan identities, 96 project families, resolution and retries, window icons and /tim icons passed")
