-- TimeIsMoney's WoW: Forever mock. dofile("tests/wow_stubs.lua") returns { New, acceptKnownStrays }.
--
-- New(saved, libGlass) starts a fresh client and returns env, captured, libFiles:
-- - env: the sandbox the addon's files run in (setfenv), holding only the names
--   allowed below; reading any other is an error ("Unvalidated global").
-- - captured: what the tests read back (messages, widgets, sounds, ...).
-- - libFiles: the files of the LibGlass-1.0 checkout at libGlass, in its XML's
--   order, or nil for the recording stand-in below.
--
-- The mechanics come from WowTestKit (tests/kit.lua loads the commit tests/kit.pin
-- names; its README is the reference): widgets that record every method called
-- (a method the build lacks reads as nil), event names checked against the pinned
-- build, timers and the clock (WoW.now, WoW.flushTimers), print (with the
-- stray-"|" check done() fails on), WoW.fire, check / eq / done. Each New() after
-- the first is Kit.freshClient(): a new core, with the assertions' counts kept.
--
-- This file adds TimeIsMoney's own client APIs, each verified in the API dump
-- (C:\Projects\WoW\References\Forever\api\forever-api-<version>.<build>.md). No
-- rendering or persistence claim: stubs cannot prove pixels.
dofile("tests/kit.lua") -- with this file, so check / eq / done are there from the start
local started = false
local function New(saved, libGlass)
    if started then Kit.freshClient() end
    started = true
    local Methods = WoW.Methods
    local captured = { messages = WoW.chat }
    local env = {
        TimeIsMoneyDB = saved, SlashCmdList = {}, _VERSION = _VERSION,
        tostring = tostring,
        print = print, -- the kit's: every line in WoW.chat (captured.messages)
        -- The client the addon's evidence names (Compat.lua); the kit's API lists are
        -- tests/kit.pin's build.
        GetBuildInfo = function() return "1.60.1", "70338", "Oct 9 2026", 16001 end,
        -- Standard Lua the simulation and host use (test_sim.lua enforces Sim's set).
        math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type,
        tonumber = tonumber, error = error, setmetatable = setmetatable, next = next, select = select,
        pcall = pcall, assert = assert,
        GetServerTime = function() return 1790000000 end,
        debugprofilestop = function() captured.clock = (captured.clock or 0) + 0.01 return captured.clock end,
    }
    local allowedNil = { TimeIsMoney = true, TimeIsMoneyDB = true, TimeIsMoneyWindow = true, TimeIsMoneyIcons = true, TimeIsMoneyConfirm = true, TimeIsMoneyHelp = true,
        TimeIsMoneySettings = true, TimeIsMoneyMinimapButton = true, TimeIsMoneyReports = true,
        GREEN_FONT_COLOR = true, NORMAL_FONT_COLOR = true, TimeIsMoneyTooltip = true }
    setmetatable(env, { __index = function(_, key)
        if allowedNil[key] then return nil end
        error("Unvalidated global: " .. tostring(key), 2)
    end })

    -- Methods the kit doesn't implement, each in the build's widget methods.
    -- WowTestKit #89: scale, GetStringWidth.
    function Methods.SetScale(w, s) w._scale = s end
    function Methods.GetScale(w) return w._scale or 1 end
    -- About 6 px per character at the window's sizes (stubs cannot measure text).
    function Methods.GetStringWidth(fs) return #tostring(fs._text or "") * 6 end
    -- WowTestKit #89: wrapped height, 14 px per line at the set width (stubs
    -- cannot measure text).
    function Methods.GetStringHeight(fs)
        local width = fs._width
        if not width or width == 0 then width = 1000 end
        local perLine = math.max(1, math.floor(width / 6))
        return 14 * math.max(1, math.ceil(#tostring(fs._text or "") / perLine))
    end
    -- Raise, recorded (the frame last raised): the kit has the method, and no
    -- stacking order to change.
    function Methods.Raise(w) captured.raised = w end
    -- WowTestKit #89: the edges RegisterForClicks registered.
    function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
    -- WowTestKit #90: the model actor (ModelScene:CreateActor, ModelSceneActor's
    -- model methods). Tests choose whether a display loads (captured.modelOK) and
    -- the box it reports once streamed (captured.modelBox, six numbers).
    function Methods.CreateActor(scene)
        local actor = WoW.newWidget("ModelSceneActor", scene)
        captured.actor = actor
        return actor
    end
    function Methods.SetModelByCreatureDisplayID(actor, id)
        actor._display = id
        captured.modelLoads = (captured.modelLoads or 0) + 1
        return captured.modelOK ~= false
    end
    function Methods.ClearModel(actor) actor._display = nil end
    function Methods.SetPosition(actor, x, y, z) actor._position = { x, y, z } end
    function Methods.SetAnimation(actor, anim) actor._animation = anim end
    function Methods.GetActiveBoundingBox(actor)
        if actor._display and captured.modelBox then return unpack(captured.modelBox) end
    end

    -- The tooltip's lines, for assertions (WowTestKit #89): SetText starts them,
    -- AddLine adds one. SetOwner keeps them, as the old stub did (the tests read a
    -- hover's lines after it; whether the client's SetOwner clears them is unmeasured).
    local coreSetText = Methods.SetText
    function Methods.SetText(w, text, ...)
        if w._type == "GameTooltip" then w.lines = { text } end
        return coreSetText(w, text, ...)
    end
    function Methods.AddLine(tt, text) tt.lines = tt.lines or {} tt.lines[#tt.lines + 1] = text end
    function Methods.SetOwner(tt, owner) tt._owner = owner end

    -- The widgets the tests look through, in creation order: font strings and
    -- textures (CreateFontString / CreateTexture); the plain parentless, nameless
    -- Frames (captured.frames: the event and wakeup frames); and every other frame
    -- (captured.widgets). The two frame lists are disjoint, as the old stub's were;
    -- WoW.frames is every frame.
    captured.fontStrings, captured.widgets, captured.textures, captured.frames = {}, {}, {}, {}
    local coreFontString, coreTexture = Methods.CreateFontString, Methods.CreateTexture
    function Methods.CreateFontString(w, ...)
        local fs = coreFontString(w, ...)
        captured.fontStrings[#captured.fontStrings + 1] = fs
        return fs
    end
    function Methods.CreateTexture(w, ...)
        local t = coreTexture(w, ...)
        captured.textures[#captured.textures + 1] = t
        return t
    end

    env.UIParent = UIParent
    UIParent._width, UIParent._height = 1024, 768
    -- The minimap (#78): a 140 px round frame centred at (500, 400) at scale 1; the
    -- cursor is WoW.cursorX, WoW.cursorY (screen pixels).
    local minimap = WoW.newWidget("Minimap", UIParent, "Minimap")
    minimap._width, minimap._height, minimap._level = 140, 140, 2
    minimap._left, minimap._right, minimap._bottom, minimap._top = 430, 570, 330, 470
    env.Minimap = minimap
    -- Frames ESC closes before the game menu (#89); the addon only edits entries.
    env.UISpecialFrames = {}
    env._G = env
    env.GetCursorPosition = GetCursorPosition
    env.GameTooltip = WoW.newWidget("GameTooltip", UIParent, "GameTooltip")
    env.GameTooltip._shown = false
    captured.glass = { applied = 0 }
    -- Icons (#21): the client resolves item icons once their data is loaded; tests
    -- choose which items are known (captured.itemIcons) and fire the load result.
    captured.itemIcons, captured.requested = {}, {}
    env.C_Item = {
        GetItemIconByID = function(id) return captured.itemIcons[id] end,
        RequestLoadItemDataByID = function(id) captured.requested[#captured.requested + 1] = id end,
        -- Item quality (#84): captured.qualities[id], nil while not loaded.
        GetItemQualityByID = function(id) return captured.qualities and captured.qualities[id] end,
        GetItemQualityColor = function(q) if q == 2 then return 0.12, 1, 0 end return 1, 1, 1 end,
    }
    -- UI sound kits (#90): recorded.
    captured.soundKits = {}
    env.C_Sound = { PlaySound = function(kit) captured.soundKits[#captured.soundKits + 1] = kit return true end }
    env.C_Spell = { GetSpellTexture = function(id) return 100000 + id end }
    -- C_Timer is the kit's (WoW.timers): RunTimers runs those queued so far, those
    -- they queue wait for the next call.
    env.C_Timer = C_Timer
    function captured:RunTimers()
        local n = #WoW.timers
        WoW.flushTimers()
        return n
    end
    env.SetPortraitTextureFromCreatureDisplayID = function(texture, id) texture.portraitDisplay = id end
    env.GetLocale = GetLocale -- the kit's: WoW.locale, enUS until a test sets one
    env.UnitFactionGroup = function() return captured.faction or "Horde" end
    captured.sounds = {}
    env.PlaySoundFile = function(id, channel) captured.sounds[#captured.sounds + 1] = { id, channel } return true end
    env.unpack = unpack
    env.GetTime = GetTime -- the kit's: WoW.now
    function captured:ItemLoaded(id, success) WoW.fire("ITEM_DATA_LOAD_RESULT", id, success) end
    if libGlass then
        -- The real library: what it needs beyond the widgets above.
        env._G, env.strmatch, env.assert, env.rawget = env, strmatch, assert, rawget
        env.Enum = {}
        env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        env.hooksecurefunc = hooksecurefunc
        env.unpack = unpack
        allowedNil.LibStub = true
    end
    local libFiles
    if libGlass then
        local xml = assert(io.open(libGlass .. "/LibGlass-1.0.xml", "rb")):read("*a"):gsub("<!%-%-.-%-%->", "")
        libFiles = {}
        for file in xml:gmatch('<Script%s+file="([^"]+)"') do libFiles[#libFiles + 1] = libGlass .. "/" .. file:gsub("\\", "/") end
    end
    -- LibGlass-1.0 stand-in: the calls the window makes, recorded. The library's own
    -- tests cover the material; here only the API shape matters.
    local glass = {}
    function glass.Apply(host, size)
        assert(size == "large" or size == "small" or size == "thin" or size == "thin_small", "glass size")
        captured.glass.applied = captured.glass.applied + 1
        return { size = size, top = env.CreateFrame("Frame", nil, host) }
    end
    -- r2: the material on a circle; the host must be square and sized first.
    function glass.Disc(host, size)
        assert(size == "disc" or size == "disc_small", "disc size")
        assert(host:GetWidth() > 0 and host:GetWidth() == host:GetHeight(), "a square, sized host")
        captured.glass.applied = captured.glass.applied + 1
        return { size = size, top = env.CreateFrame("Frame", nil, host) }
    end
    -- A font string with the library's font (the real one calls SetFont), so the
    -- kit lets the window set its text.
    function glass.Font(parent, size, justify)
        local fs = parent:CreateFontString()
        fs._font = { "Fonts\\FRIZQT__.TTF", size or 12, "" }
        return fs
    end
    -- A bar with the library's fill texture (the real one calls SetStatusBarTexture).
    function glass.Bar(parent, height)
        local bar = env.CreateFrame("StatusBar", nil, parent)
        bar._fill = WoW.newWidget("Texture", bar)
        return bar
    end
    local INSETS = { large = 6, small = 3, thin = 4, thin_small = 2 } -- LibGlass r3 SIZES
    function glass.Inset(size) return INSETS[size or "large"] end
    -- r3: one surface's own tint (none = its built colour) and its disabled look.
    function glass.SetSurfaceTint(g, r, gr, b, a) g.surfaceTint = r and { r, gr, b, a } or nil end
    function glass.SetSurfaceEnabled(g, enabled) g.surfaceEnabled = enabled end
    function glass.ContentLevel(host) return host:GetFrameLevel() + 2 end
    function glass.SetBar(bar, max, value) bar.max, bar.value = max, value end
    if not libGlass then env.LibStub = function(name)
        assert(name == "LibGlass-1.0")
        return { New = function(self) assert(self ~= nil, "colon call") return glass end }
    end end
    env.CreateFrame = function(kind, name, parent, template)
        -- The addon's own tooltip (#89): recorded, and answered by the tooltip
        -- recorder so tests read its lines in one place.
        if kind == "GameTooltip" then
            captured.tooltipCreated = { name = name, parent = parent, template = template }
            if name then env[name] = env.GameTooltip end
            return env.GameTooltip
        end
        local w = CreateFrame(kind, name, parent, template)
        if name then env[name] = w end
        if kind ~= "Frame" or parent ~= nil or name ~= nil then captured.widgets[#captured.widgets + 1] = w
        else captured.frames[#captured.frames + 1] = w end
        return w
    end
    function captured:Fire(addonName) WoW.fire("ADDON_LOADED", addonName, false) end
    function captured:Logout() WoW.fire("PLAYER_LOGOUT") end
    Kit.strict({})
    return env, captured, libFiles
end
-- FINDING (#114): /tim help's developer line "/tim anim|voice|cue <id>" holds
-- bare "|"s, which the client reads as escapes. done() fails on any stray "|";
-- a test that prints the help lets exactly that line through until it's
-- fixed, so any other stray still fails. Returns how many it let through.
local function acceptKnownStrays()
    local keep, known = {}, 0
    for _, line in ipairs(WoW.strays) do
        if line:find("/tim anim|voice|cue <id>.", 1, true) then known = known + 1
        else keep[#keep + 1] = line end
    end
    WoW.strays = keep
    return known
end

return { New = New, acceptKnownStrays = acceptKnownStrays }
