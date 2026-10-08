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
wait(1)
assert(Director.state == "live", "the model is live")
for _ = 1, 3 do Window.Toggle() Window.Toggle() end
local said = voices()
for i = 2, #said do assert(said[i] ~= said[i - 1], "no repeat") end
local seen = {}
for _, id in ipairs(said) do seen[id] = true end
assert(seen[550785] and seen[550786] and seen[550773], "all three greetings")

-- A new report: the newest line fades in, Gazlowe talks, and the first answer is a
-- deal line (his voice, at most once a minute).
local game = Host.game
local before = #captured.sounds
game:displayMessage("AutoClippers available for purchase")
wait(0.1)
assert(captured.actor.animation == Director.TALK_ANIM, "Gazlowe talks")
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

-- Developer commands to pick the IDs in game.
env.SlashCmdList.TIMEISMONEY("anim 64")
assert(captured.actor.animation == 64)
env.SlashCmdList.TIMEISMONEY("voice 550784")
assert(captured.sounds[#captured.sounds][1] == 550784)
env.SlashCmdList.TIMEISMONEY("cue 891")
assert(captured.soundKits[#captured.soundKits] == 891)

print("cues: rotating greetings, the report cue (talk, deal line, soft sound, throttle, settings), fade-in, New tags and developer commands passed")
