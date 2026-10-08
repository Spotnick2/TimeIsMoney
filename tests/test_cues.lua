-- Cues (#90): Gazlowe's rotating greeting, the report cue (talk, sound or a deal
-- line, throttled), the newest line fading in, and "New" tags on things that
-- appear after the first draw.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window, Director = ns.Host, ns.Window, ns.Director
captured.modelBox = { -0.4, -0.5, -0.9, 0.4, 0.5, 0.9 }

-- The window's own redraws: each 0.1 s.
local function wait(seconds)
    for _ = 1, math.floor(seconds * 10 + 0.5) do Window.frame.scripts.OnUpdate(Window.frame, 0.1) end
end
local function voices()
    local out = {}
    for _, s in ipairs(captured.sounds) do out[#out + 1] = s[1] end
    return out
end

-- Greetings rotate, never the same twice in a row.
env.SlashCmdList.TIMEISMONEY("start")
-- The first greeting comes while the model loads: he talks once it is in.
assert(Director.state == "loading" and Director.talkWhenLive, "the talk waits for the model")
wait(1)
assert(Director.state == "live", "the model is live")
assert(captured.actor.animation == Director.TALK_ANIM or captured.actor.animation == 0, "he talked")
wait(Director.TALK_SECONDS)
-- Opening the window again: the greeting and the talk together.
Window.Toggle() Window.Toggle()
assert(captured.actor.animation == Director.TALK_ANIM, "he says it with the animation")
wait(Director.TALK_SECONDS + 0.1)
assert(captured.actor.animation == 0, "back to idle")
for _ = 1, 3 do Window.Toggle() Window.Toggle() end
local said = voices()
for i = 2, #said do assert(said[i] ~= said[i - 1], "no repeat") end
local seen = {}
for _, id in ipairs(said) do seen[id] = true end
assert(seen[550785] and seen[550786] and seen[550773], "all three greetings")

-- A new report: the newest line fades in, Gazlowe talks, and the first answer is a
-- deal line (his voice, at most once a minute).
local game = Host.game
-- The talk animation the owner picked in the client (60, Talk).
assert(Director.TALK_ANIM == 60)
wait(Director.DEAL_COOLDOWN + Director.CUE_COOLDOWN)
local before = #captured.sounds
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(captured.actor.animation == 60, "Gazlowe talks")
assert(#captured.sounds == before + 1 and captured.sounds[#captured.sounds][2] == "Dialog", "a deal line")
local deal = captured.sounds[#captured.sounds][1]
assert(deal == 550772 or deal == 550784 or deal == 550782)
assert(Director.strip.reports[1].alpha < 1, "the newest line starts faded")
wait(1)
assert(Director.strip.reports[1].alpha == Director.REPORT_ALPHA[1], "and fades in")
wait(2)
assert(captured.actor.animation == 0, "back to idle after the talk")
-- Another report within the cooldown: no cue.
local kits = #captured.soundKits
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(#captured.soundKits == kits and #captured.sounds == before + 1, "throttled")
-- After the cooldown, within the deal minute: the soft sound.
wait(Director.CUE_COOLDOWN)
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(#captured.soundKits == kits + 1 and captured.soundKits[#captured.soundKits] == Director.CUE_SOUNDKIT, "the soft sound")
-- Voice off: never a deal line; sound off: silence (still the talk and the fade).
ns.Settings.Set("voice", false)
wait(Director.DEAL_COOLDOWN)
local n = #captured.sounds
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(#captured.sounds == n, "no voice when it is off")
ns.Settings.Set("reportSound", false)
wait(Director.CUE_COOLDOWN)
kits = #captured.soundKits
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(#captured.soundKits == kits, "no sound when it is off")
ns.Settings.Set("voice", true)
ns.Settings.Set("reportSound", true)

-- "New" tags: nothing shown at the first draw is new; a row that appears later is,
-- until hovered or NEW_SECONDS later.
local function tagNear(text)
    for _, fs in ipairs(captured.fontStrings) do
        if fs.text == "New" and h.visible(fs) then return fs end
    end
end
assert(not tagNear(), "nothing is new at first")
game.S.autoClipperFlag = 1 -- Gizmos appear in Production
wait(0.1)
assert(tagNear(), "the Gizmos row is new")
local area
for _, w in ipairs(captured.widgets) do if w.itemKey == "autoClippers" and h.visible(w) then area = w end end
area.scripts.OnEnter(area)
area.scripts.OnLeave(area)
wait(0.1)
-- The row's tag clears on hover; the Buy Gizmo button below it is its own row.
local buy = h.button("btnMakeClipper")
assert(buy.newOf and buy.newOf.newUntil, "the Buy Gizmo action is new too")
wait(Window.NEW_SECONDS)
assert(not tagNear(), "tags expire")
-- A whole new card tags its title, not each row.
game.S.compFlag = 1
wait(0.1)
local tags = 0
for _, fs in ipairs(captured.fontStrings) do if fs.text == "New" and h.visible(fs) then tags = tags + 1 end end
assert(tags >= 1 and tags <= 2, "the new card's title (and nothing per row): " .. tags)

-- No cue for reports that came while the window was hidden (the greeting plays).
wait(Director.DEAL_COOLDOWN)
Window.frame:Hide()
game:displayMessage("AutoClippers available for purchase")
local soundsBefore, kitsBefore = #captured.sounds, #captured.soundKits
Window.Toggle()
wait(0.1)
assert(#captured.sounds == soundsBefore + 1 and #captured.soundKits == kitsBefore, "the greeting only")
-- No cue on a new company.
wait(Director.CUE_COOLDOWN)
soundsBefore, kitsBefore = #captured.sounds, #captured.soundKits
Window.NewGame()
Window.dialog.yes.scripts.OnClick(Window.dialog.yes)
wait(0.1)
assert(#captured.soundKits == kitsBefore and #captured.sounds == soundsBefore, "a new company is no report")
game = Host.game
-- No cue for a message the strip does not show.
wait(Director.CUE_COOLDOWN)
kitsBefore = #captured.soundKits
game:displayMessage("Some unmapped reference text")
wait(0.1)
assert(#captured.soundKits == kitsBefore, "no cue for an unshown report")
-- Whoever speaks, the report sound plays (Gazlowe's lines only when he speaks).
local current = ns.Dialogue.Current
ns.Dialogue.Current = function() return ns.Dialogue.LEDGER, "beat.welcome" end
wait(Director.CUE_COOLDOWN)
kitsBefore, soundsBefore = #captured.soundKits, #captured.sounds
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(#captured.soundKits == kitsBefore + 1 and #captured.sounds == soundsBefore, "the sound, not his voice")
ns.Dialogue.Current = current

-- Projects: paging never makes old offers "New"; a new projects card tags its title only.
local function visibleTags()
    local n = 0
    for _, fs in ipairs(captured.fontStrings) do if fs.text == "New" and h.visible(fs) then n = n + 1 end end
    return n
end
wait(Window.NEW_SECONDS)
assert(visibleTags() == 0)
for _, e in ipairs(ns.Workshop.projects) do
    if #game.S.activeProjects >= 30 then break end
    game.S.activeProjects[#game.S.activeProjects + 1] = { id = e.id }
    game.projectElements[e.id] = true
end
game.S.projectsFlag = 1
wait(0.1)
assert(visibleTags() <= 1, "the new projects card: its title only, not every project")
wait(Window.NEW_SECONDS)
local card
for _, w in ipairs(captured.widgets) do if w.label and w.label.text == "Next" and h.visible(w) then card = w end end
assert(card, "the offers span pages")
card.scripts.OnClick(card)
wait(0.1)
assert(visibleTags() == 0, "the next page's offers were already seen")

-- Developer commands to pick the IDs in game.
env.SlashCmdList.TIMEISMONEY("anim 64")
assert(captured.actor.animation == 64)
env.SlashCmdList.TIMEISMONEY("voice 550784")
assert(captured.sounds[#captured.sounds][1] == 550784)
env.SlashCmdList.TIMEISMONEY("cue 891")
assert(captured.soundKits[#captured.soundKits] == 891)

-- Hover dismisses every kind of tag (Codex review of #92): a card title, a plain
-- stat row, and a bulk-action row (its tag on the group's last button).
local function tagOf(thing) return thing.newTag and h.visible(thing.newTag) end
local function cardTitled(title)
    for _, column in ipairs(Window.columns) do
        for _, card in ipairs(column) do if card.title.text == title then return card end end
    end
end
game.S.investmentEngineFlag = 1
wait(0.1)
local invest = assert(cardTitled("Cartel Investments"))
assert(tagOf(invest) and invest.newArea and h.visible(invest.newArea), "a new card: its title tagged, with a hover area")
invest.newArea.scripts.OnEnter(invest.newArea)
wait(0.1)
assert(not tagOf(invest) and invest.newUntil == nil, "hovering the title clears it")
-- A plain stat row (Revenue per second, after its project) appears in a shown card.
game.S.revPerSecFlag = 1
wait(0.1)
local sales = assert(cardTitled("Sales"))
local revenue
for _, row in ipairs(sales.rows) do if row.label and row.label.text == "Revenue per second" then revenue = row end end
assert(revenue and tagOf(revenue) and revenue.newArea, "a plain row: tagged, with a hover area")
revenue.newArea.scripts.OnEnter(revenue.newArea)
wait(0.1)
assert(not tagOf(revenue), "hovering the label clears it")
-- A bulk-action row (Reapers +10/+100/+1k) appears in the already shown Copper
-- Production card.
game.S.humanFlag, game.S.wireProductionFlag = 0, 1
wait(0.1)
wait(Window.NEW_SECONDS)
game.S.harvesterFlag = 1
wait(0.1)
local wireCard = assert(cardTitled("Copper Production"))
local bulk
for _, row in ipairs(wireCard.rows) do if row.buttons and row.buttons[1].id == "btnHarvesterx10" then bulk = row end end
assert(bulk and tagOf(bulk), "the bulk row is tagged")
local point = bulk.newTag.point
assert(point and point[2] == bulk.buttons[#bulk.buttons], "anchored on the group's last button")
assert(bulk.buttons[1].newOf == bulk, "its buttons know their row")
bulk.buttons[1].scripts.OnEnter(bulk.buttons[1])
bulk.buttons[1].scripts.OnLeave(bulk.buttons[1])
wait(0.1)
assert(not tagOf(bulk), "hovering a bulk button clears it")

print("cues: rotating greetings, the report cue (talk, deal line, soft sound, throttle, settings), fade-in, New tags and developer commands passed")
