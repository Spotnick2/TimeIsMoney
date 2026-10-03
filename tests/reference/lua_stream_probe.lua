-- Developer probe: lua lua_stream_probe.lua <stream.json> <site=at>...
-- Draws once per argument from the recorded stream and writes the draw events.
local dir = arg[0]:match("^(.*)[/\\]") or "."
local RecordedRandom = dofile(dir .. "/RecordedRandom.lua")
local file = assert(io.open(arg[1], "rb"))
local text = file:read("*a")
file:close()
local stream = RecordedRandom.parse(text)
for i = 2, #arg do
    local site, at = arg[i]:match("^(.-)=(%d+)$")
    if not site then error("Expected site=at: " .. arg[i]) end
    stream:draw(site, tonumber(at))
end
io.write(RecordedRandom.encodeLog(stream.log))
