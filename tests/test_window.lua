-- The ledger window (#20): what it shows, that its controls route through the host,
-- and that drawing it never changes the company.
local Stubs = dofile("tests/wow_stubs.lua")

local files = {}
for line in io.lines("TimeIsMoney.toc") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" and line:gsub("\\", "/"):sub(1, 5) ~= "Libs/" then
        files[#files + 1] = line
    end
end

-- The real LibGlass-1.0 when a checkout is at hand (LIBGLASS, which CI's Windows
-- job sets to the pinned ref, else ..\LibGlass); otherwise the recording stand-in.
local libGlass = os.getenv("LIBGLASS")
if libGlass == "none" then
    libGlass = nil -- forces the stand-in
elseif not libGlass or libGlass == "" then
    libGlass = nil
    local probe = io.open("../LibGlass/LibGlass-1.0.xml", "rb")
    if probe then probe:close() libGlass = "../LibGlass" end
end
local env, captured, libFiles = Stubs.New(nil, libGlass)
for _, path in ipairs(libFiles or {}) do
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("TimeIsMoney", {})
end
local ns = {}
for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("TimeIsMoney", ns)
end
captured:Fire("TimeIsMoney")
local View, Host, Window = ns.View, ns.Host, ns.Window

-- Display text: one reference unit is one silver; counts keep their sign.
assert(View.coins(0.25) == "25c" and View.coins(1000000) == "10,000g" and View.coins(0) == "0c")
assert(View.coins(1.5) == "1s 50c" and View.coins(-0.05) == "-5c")
assert(View.count(1234567.4) == "1,234,567" and View.count(-12) == "-12" and View.count(0 / 0) == "NaN")
assert(View.count(1e300):find("e%+300"))
-- Price tags in Time Is Money terms, the reference's computed ones included.
local S0 = { bribe = 1000000, qChipCost = 10000, threnodyCost = 50000, standardOps = 1234, project51 = { flag = 0 } }
assert(View.priceTag("project1", S0) == "(750 Operations)")
assert(View.priceTag("project2", S0) == "(1 Board Trust)")
assert(View.priceTag("project40b", S0) == "(10,000g)")
assert(View.priceTag("project51", S0) == "(10,000 Operations)")
-- After a chip purchase the reference rebuilds project51's tag without separators.
S0.project51 = { flag = 1 }
S0.qChipCost = 15000
assert(View.priceTag("project51", S0) == "(15000 Operations)")
-- Rounded to zero shows no sign.
assert(View.count(-0.3) == "0" and View.coins(-0.001) == "0c")
assert(View.priceTag("project133", S0) == "(50,000 Ingenuity, 20,000 Cunning)")
assert(View.priceTag("project216", S0) == "(1,234 Operations)")
-- Panels follow buttonUpdate, including its strict comparisons: creativityOn is a
-- boolean, so creativityOn === 0 never holds and its row shows with the Ledger.
local panels = View.panels({ wireBuyerFlag = 0, investmentEngineFlag = 0, strategyEngineFlag = 0, megaClipperFlag = 0,
    autoClipperFlag = 0, revPerSecFlag = 0, compFlag = 0, creativityOn = false, projectsFlag = 0, humanFlag = 1, qFlag = 0 })
assert(panels.business and panels.manufacturing and panels.trust and not panels.computing and panels.creativity)
assert(not panels.projects and not panels.autoClippers and not panels.wireBuyer)

-- No company: /tim says how to start one; the window is not built.
env.SlashCmdList.TIMEISMONEY("")
assert(captured.messages[#captured.messages]:find("/tim start", 1, true) and Window.frame == nil)

-- /tim start opens the window over the new company.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
assert(game and Window.frame and Window.frame:IsShown() and env.TimeIsMoneyWindow == Window.frame)
if libGlass then
    local lib = env.LibStub("LibGlass-1.0")
    assert(lib.MEDIA == [[Interface\AddOns\TimeIsMoney\Libs\LibGlass-1.0\Media\]], "embedded path")
else
    assert(captured.glass.applied > 0, "drawn with the glass material")
end

local function button(id)
    for _, w in ipairs(captured.widgets) do
        if w.kind == "Button" and w.id == id and w.shown then return w end
    end
end
local function shownText(fragment)
    for _, fs in ipairs(captured.fontStrings) do
        if fs.shown and fs.text and tostring(fs.text):find(fragment, 1, true) then return fs end
    end
end

-- The opening: production and sales; no computing, no projects yet.
assert(shownText("Handfuls of Copper Bolts") and shownText("Company Funds") and shownText("Board Trust"))
assert(not button("btnAddProc") and not button("btnMakeClipper"))
local make = assert(button("btnMakePaperclip"))
assert(make.enabled and make.label.text == "Make Copper Bolts")
-- Text sits on the glass's top layer, above the rim (LibGlass review of #56).
assert(make.label.parent == make.glass.top, "button text above the rim")
-- Square buttons are 32x32: sliced masks fail on boxes small in both directions.
local raise = assert(button("btnRaisePrice"))
assert(raise.width == 32 and raise.height == 32)
-- Disabled square buttons say so with a symbol, not only colour.
game.S.margin = 0.01
Host.update(0.02)
Window.Refresh()
assert(button("btnLowerPrice").label.text == "(-)" and button("btnRaisePrice").label.text == "+")

-- Drawing never changes the company: the state is identical after many refreshes.
local function digest(t, seen)
    seen = seen or {}
    if type(t) ~= "table" then return tostring(t) end
    if seen[t] then return "<cycle>" end
    seen[t] = true
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        if v == nil then v = t[tonumber(k)] end
        out[#out + 1] = k .. "=" .. digest(v, seen)
    end
    return "{" .. table.concat(out, ",") .. "}"
end
local before = digest(game.S) .. digest(game.disabled) .. digest(game.readouts)
local draws = Host.random.count
for _ = 1, 20 do Window.Refresh() end
assert(digest(game.S) .. digest(game.disabled) .. digest(game.readouts) == before and Host.random.count == draws,
    "refreshing the window changed the company")

-- A control routes through the host: one click makes one handful.
local clips = game.S.clips
make.scripts.OnClick(make)
assert(game.S.clips == clips + 1)

-- A disabled control says so in its label, not only in colour.
game.S.funds = 0
Host.update(0.02)
Window.Refresh()
local buy = assert(button("btnBuyWire"))
assert(not buy.enabled and buy.label.text:find("(not yet)", 1, true))

-- Projects appear as the game offers them, with their Time Is Money title and cost.
game.S.funds = 100
game.S.projectsFlag = 1 -- the panel opens later in play (at the computing milestone)
Host.update(0.02) -- buttonUpdate enables the purchase
assert(Host.click("btnMakeClipper") and game.S.clipmakerLevel == 1)
Host.update(0.05)
Window.Refresh()
assert(button("btnMakeClipper"), "gizmos show once affordable")
local project = assert(button("projectButton1"), "Precision Dies on offer")
assert(project.label.text:find("Precision Dies", 1, true) and project.label.text:find("750 Operations", 1, true))

-- A long offer list on a short screen: the window stays within the screen and
-- paging reaches every offer (Codex review of #56).
env.UIParent.height = 500
local saved = game.S.activeProjects
local offers = {}
for i = 1, 19 do
    local entry = ns.Workshop.projects[i]
    offers[i] = game.S[entry.name]
end
game.S.activeProjects = offers
Window.Refresh()
assert(Window.frame.height <= 500, "window taller than the screen: " .. tostring(Window.frame.height))
local reached, pages = {}, 0
local function nav(label)
    for _, w in ipairs(captured.widgets) do
        if w.kind == "Button" and w.shown and w.label and w.label.text and w.label.text:find(label, 1, true) then return w end
    end
end
repeat
    pages = pages + 1
    for _, w in ipairs(captured.widgets) do
        if w.kind == "Button" and w.shown and w.id and w.id:find("^projectButton") then reached[w.id] = true end
    end
    local nextPage = nav("Next")
    local more = nextPage and nextPage.enabled
    if more then nextPage.scripts.OnClick(nextPage) end
until not more or pages > 10
for i = 1, 19 do assert(reached[offers[i].id], "unreachable offer " .. offers[i].id) end
assert(pages > 1 and pages <= 10)
game.S.activeProjects = saved
env.UIParent.height = 768
Window.Refresh()

-- Hidden: the window stops drawing, the company keeps running.
Window.Toggle()
assert(not Window.frame:IsShown())
local now = game.clock.now
local text = make.label.text
Host.update(0.5)
Window.Refresh()
assert(game.clock.now > now, "hiding the window must not pause the company")
assert(make.label.text == text)
Window.Toggle()
assert(Window.frame:IsShown())

print((libGlass and "window (real LibGlass at " .. libGlass .. ")" or "window (LibGlass stand-in)")
    .. ": display text, price tags, panel rules, routing, no state change from drawing, disabled labels, projects and hidden refresh passed")
