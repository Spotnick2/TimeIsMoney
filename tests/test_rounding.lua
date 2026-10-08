-- Counts as the reference shows them, and why a control is unavailable (#73).
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

-- The reference's rounding: formatWithCommas keeps the digits before the point
-- (toward zero); bolts use Math.ceil; rates and power use Math.round.
assert(View.count(0.6) == "0" and View.count(1.99) == "1" and View.count(-12000.7) == "-12,000")
assert(View.count(999.4, "ceil") == "1,000" and View.count(999, "ceil") == "999")
assert(View.count(2.5, "round") == "3" and View.count(2.49, "round") == "2" and View.count(-2.5, "round") == "-2")
assert(View.count(-0.3) == "0" and View.count(-0.3, "ceil") == "0", "no -0")

-- In the window: 999.4 bolts read 1,000 (as the 1,000-handful report does), and
-- Copper Bars round down (0.6 reads 0 while Make is unavailable).
local function exactly(text)
    for _, fs in ipairs(captured.fontStrings) do
        if h.visible(fs) and fs.text == text then return fs end
    end
end
env.SlashCmdList.TIMEISMONEY("start")
local S = Host.game.S
S.clips, S.wire = 999.4, 1234.6
Window.Refresh()
assert(exactly("1,000"), "bolts round up")
assert(exactly("1,234") and not exactly("1,235"), "bars round down: a partial bar is not shown as a whole one")
S.wire = 0.6
Host.game.disabled.btnMakePaperclip = true
Window.Refresh()

-- The tooltip says what is missing.
local make = h.button("btnMakePaperclip")
assert(make and not make:IsEnabled(), "Make is unavailable")
make.scripts.OnEnter(make)
local lines = env.GameTooltip.lines
assert(lines and lines[#lines]:find("Out of Copper Bars", 1, true), "Make says it needs a whole bar")
make.scripts.OnLeave(make)

-- Every control the simulation can disable has a reason, in the window's terms.
S.funds, S.wireCost = 0, 20
assert(View.unavailable("btnBuyWire", S) == "Not enough Company Funds.")
S.tourneyInProg = 1
assert(View.unavailable("btnNewTournament", S) == "A tournament is already running.")
S.tourneyInProg = 0
assert(View.unavailable("btnNewTournament", S) == "Not enough Operations.")
-- Run: before setup, during the rounds, after they finish (Codex review of #76).
assert(View.unavailable("btnRunTournament", S) == "Set up a new tournament first.")
S.tourneyInProg = 1
assert(View.unavailable("btnRunTournament", S) == "A tournament is already running.")
S.tourneyInProg = 0
assert(View.unavailable("btnRunTournament", S) == "Set up a new tournament first.")
S.probeTrust, S.maxTrust = 5, 5
assert(View.unavailable("btnIncreaseProbeTrust", S) == "Dragonling Trust is at its maximum.")
assert(View.unavailable("btnRaiseProbeSpeed", S) and View.unavailable("projectButton1", S))
-- Every control id the simulation assigns a disabled state to (Sim sources).
local checked = 0
for _, file in ipairs(ns.Reference.files) do
    local text = assert(io.open(file, "rb")):read("*a")
    for id in text:gmatch("disabled%.(btn%w+) =") do
        assert(View.unavailable(id, S), "a reason for " .. id)
        checked = checked + 1
    end
end
assert(checked >= 38, "the scan found the controls: " .. checked)
-- An available control adds nothing to its tooltip.
local buy = h.button("btnBuyWire")
if buy then
    S.funds = 1e9
    Host.game.disabled.btnBuyWire = false
    Window.Refresh()
    buy.scripts.OnEnter(buy)
    for _, line in ipairs(env.GameTooltip.lines or {}) do assert(not line:find("Not enough", 1, true)) end
    buy.scripts.OnLeave(buy)
end

print((libGlass and "rounding (real LibGlass)" or "rounding (LibGlass stand-in)")
    .. ": reference rounding per count, partial bars, bolts at 1,000 and unavailable reasons passed")
