-- Loads the addon for the window tests: the TOC's files into the stub client, with
-- the real LibGlass-1.0 when a checkout is at hand (LIBGLASS, which CI's Windows job
-- sets to the pinned ref, else ..\LibGlass) and the recording stand-in otherwise
-- (LIBGLASS=none forces it). Returns env, captured, ns and libGlass (or nil).
local Stubs = dofile("tests/wow_stubs.lua")

local function Load()
    local files = {}
    for line in io.lines("TimeIsMoney.toc") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:gsub("\\", "/"):sub(1, 5) ~= "Libs/" then
            files[#files + 1] = line
        end
    end
    local libGlass = os.getenv("LIBGLASS")
    if libGlass == "none" then
        libGlass = nil
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
    return env, captured, ns, libGlass
end

-- Shown widgets and text, for assertions.
local function Helpers(captured)
    local h = {}
    -- Visible as the client decides: shown, and every parent shown.
    local function visible(w)
        while w do
            if w.shown == false then return false end
            w = w.parent
        end
        return true
    end
    h.visible = visible
    function h.button(id)
        for _, w in ipairs(captured.widgets) do
            if w.kind == "Button" and w.id == id and visible(w) then return w end
        end
    end
    function h.labelled(text)
        for _, w in ipairs(captured.widgets) do
            if w.kind == "Button" and visible(w) and w.label and w.label.text == text then return w end
        end
    end
    function h.shownText(fragment)
        for _, fs in ipairs(captured.fontStrings) do
            if visible(fs) and fs.text and tostring(fs.text):find(fragment, 1, true) then return fs end
        end
    end
    function h.digest(t, seen)
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
            out[#out + 1] = k .. "=" .. h.digest(v, seen)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return h
end

return { Load = Load, Helpers = Helpers }
