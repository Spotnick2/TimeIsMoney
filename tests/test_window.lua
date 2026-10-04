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

local env, captured = Stubs.New(nil)
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
local S0 = { bribe = 1000000, qChipCost = 10000, threnodyCost = 50000, standardOps = 1234 }
assert(View.priceTag("project1", S0) == "(750 Operations)")
assert(View.priceTag("project2", S0) == "(1 Board Trust)")
assert(View.priceTag("project40b", S0) == "(10,000g)")
assert(View.priceTag("project51", S0) == "(10,000 Operations)")
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
assert(captured.glass.applied > 0, "drawn with the glass material")

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

print("window: display text, price tags, panel rules, routing, no state change from drawing, disabled labels, projects and hidden refresh passed")
