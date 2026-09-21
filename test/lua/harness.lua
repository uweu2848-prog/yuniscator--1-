-- End-to-end test harness: runs the REAL loader + REAL built payload against the
-- REAL server over HTTP, with a mocked Roblox environment (no Roblox needed).
--
-- Needs a Lua 5.3 with luasocket (TeX Live's `texlua` has both):
--     texlua test/lua/harness.lua test/lua/scenarios/basic.lua
--
-- Environment variables:
--     SCORP_URL     http://127.0.0.1:PORT
--     MY_ID MY_NAME MY_DISPLAY JOB_ID
--     OTHERS        "id:name:display,id:name:display"   other players standing in the mock server
--     TAMPER        none | spy_global | wrap_request | strong
--     OWNER_KEY     sets getgenv().SCORP_OWNER_KEY

local scriptDir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = scriptDir .. "/?.lua;" .. package.path
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")

local H = { warnings = {}, prints = {}, controls = {}, unloads = {}, notifies = {}, requests = {} }
local function env(name, default) return os.getenv(name) or default end

local URL = env("SCORP_URL", "http://127.0.0.1:3000")
local MY_ID = tonumber(env("MY_ID", "5001"))
local MY_NAME = env("MY_NAME", "Tester")
local MY_DISPLAY = env("MY_DISPLAY", MY_NAME)
local JOB_ID = env("JOB_ID", "job-1")
local TAMPER = env("TAMPER", "none")

-- ───────────────────────────────────────────────────────────────────────────
--  Virtual scheduler (task.spawn / task.wait / task.delay)
-- ───────────────────────────────────────────────────────────────────────────
local clock = 0
local sleepers = {}
local function resume(co, ...)
    local ok, res = coroutine.resume(co, ...)
    if not ok then
        io.stderr:write("[thread error] " .. tostring(res) .. "\n")
        H.threadErrors = (H.threadErrors or 0) + 1
    elseif coroutine.status(co) == "suspended" and type(res) == "table" and res.wait then
        sleepers[#sleepers + 1] = { co = co, wake = clock + res.wait }
    end
end
local function spawn(fn, ...)
    local co = coroutine.create(fn)
    resume(co, ...)
    return co
end
function H.advance(seconds)
    local target = clock + seconds
    while true do
        local best, bi
        for i, s in ipairs(sleepers) do
            if s.wake <= target and (not best or s.wake < best.wake) then best, bi = s, i end
        end
        if not best then break end
        table.remove(sleepers, bi)
        clock = best.wake
        resume(best.co)
    end
    clock = target
end
task = {
    spawn = function(fn, ...) return spawn(fn, ...) end,
    wait = function(n) coroutine.yield({ wait = n or 0.03 }) return n end,
    delay = function(n, fn) spawn(function() task.wait(n) fn() end) end,
}

-- ───────────────────────────────────────────────────────────────────────────
--  Roblox data types (just enough for the nametag code)
-- ───────────────────────────────────────────────────────────────────────────
local Color3MT = {}
Color3MT.__index = Color3MT
function Color3MT:Lerp(o, a)
    return setmetatable({ R = self.R + (o.R - self.R) * a, G = self.G + (o.G - self.G) * a, B = self.B + (o.B - self.B) * a }, Color3MT)
end
Color3 = { fromRGB = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, Color3MT) end }
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
    new = function(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end,
    fromOffset = function(x, y) return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } } end,
    fromScale = function(x, y) return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } } end,
}
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
ColorSequence = { new = function(a, b) return { a, b } end }
TweenInfo = { new = function(...) return { ... } end }
Enum = setmetatable({}, { __index = function(_, cat)
    return setmetatable({}, { __index = function(_, item) return cat .. "." .. item end })
end })
math.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ───────────────────────────────────────────────────────────────────────────
--  Instances
-- ───────────────────────────────────────────────────────────────────────────
local Inst = {}
local methods = {}
local function setParent(inst, parent)
    local old = rawget(inst, "_parent")
    if old then
        for i, c in ipairs(old._children) do if c == inst then table.remove(old._children, i) break end end
    end
    rawset(inst, "_parent", parent)
    if parent then table.insert(parent._children, inst) end
end
Inst.__index = function(t, k)
    if k == "Parent" then return rawget(t, "_parent") end
    return methods[k]
end
Inst.__newindex = function(t, k, v)
    if k == "Parent" then setParent(t, v) else rawset(t, k, v) end
end
local function newInstance(class)
    return setmetatable({ ClassName = class, Name = class, _children = {}, Destroyed = false }, Inst)
end
function methods.Destroy(self)
    rawset(self, "Destroyed", true)
    setParent(self, nil)
    for _, c in ipairs({ table.unpack(self._children) }) do c:Destroy() end
end
function methods.GetChildren(self) return { table.unpack(self._children) } end
function methods.FindFirstChild(self, name)
    for _, c in ipairs(self._children) do if c.Name == name then return c end end
    return nil
end
methods.WaitForChild = methods.FindFirstChild
function H.find(root, name)
    for _, c in ipairs(root._children) do
        if c.Name == name then return c end
        local d = H.find(c, name)
        if d then return d end
    end
    return nil
end
Instance = { new = newInstance }

-- ───────────────────────────────────────────────────────────────────────────
--  Players / services
-- ───────────────────────────────────────────────────────────────────────────
local players = {}
local function newPlayer(id, name, display)
    local p = newInstance("Player")
    p.UserId, p.Name, p.DisplayName = id, name, display or name
    local model = newInstance("Model")
    model.Name = name
    local head = newInstance("Part")
    head.Name = "Head"
    head.Parent = model
    p.Character = model
    players[#players + 1] = p
    return p
end
local me = newPlayer(MY_ID, MY_NAME, MY_DISPLAY)
local gui = newInstance("PlayerGui") gui.Name = "PlayerGui" gui.Parent = me
for entry in (env("OTHERS", "")):gmatch("[^,]+") do
    local id, name, display = entry:match("^(%d+):([^:]+):?(.*)$")
    if id then newPlayer(tonumber(id), name, display ~= "" and display or name) end
end

local coreGui = newInstance("CoreGui") coreGui.Name = "CoreGui"
local hui = newInstance("ScreenGui") hui.Name = "hui"

local services = {
    Players = {
        LocalPlayer = me,
        GetPlayers = function() return players end,
        GetPlayerByUserId = function(_, id) for _, p in ipairs(players) do if p.UserId == id then return p end end end,
        GetUserThumbnailAsync = function(_, id) return "rbxthumb://type=AvatarHeadShot&id=" .. id, true end,
    },
    HttpService = {
        JSONEncode = function(_, v) return json.encode(v) end,
        JSONDecode = function(_, s) return json.decode(s) end,
        GenerateGUID = function() return "guid" end,
    },
    TweenService = { Create = function() return { Play = function() end, Cancel = function() end } end },
    TextService = { GetTextSize = function(_, text, size) return Vector2.new(#text * size * 0.55, size) end },
    CoreGui = coreGui,
    RbxAnalyticsService = { GetClientId = function() return env("HWID", "HWID-" .. MY_ID) end },
}
game = {
    JobId = JOB_ID,
    PlaceId = 123456,
    GetService = function(_, name)
        services[name] = services[name] or newInstance(name)
        return services[name]
    end,
    HttpGet = function() error("HttpGet should not be used by the payload") end,
}

-- ───────────────────────────────────────────────────────────────────────────
--  Executor globals: real HTTP over luasocket
-- ───────────────────────────────────────────────────────────────────────────
local natives = {}
local function native(fn) natives[fn] = true return fn end
local function realRequest(opts)
    local chunks = {}
    local headers = {}
    for k, v in pairs(opts.Headers or {}) do headers[k] = v end
    local body = opts.Body
    if body then headers["Content-Length"] = tostring(#body) end
    local ok, code = http.request({
        url = opts.Url,
        method = opts.Method or "GET",
        headers = headers,
        source = body and ltn12.source.string(body) or nil,
        sink = ltn12.sink.table(chunks),
    })
    if not ok then error("http failed: " .. tostring(code)) end
    local res = { Success = code >= 200 and code < 300, StatusCode = code, Body = table.concat(chunks) }
    H.requests[#H.requests + 1] = { path = opts.Url:gsub("^https?://[^/]+", ""), status = code }
    return res
end
request = native(function(opts) return realRequest(opts) end)

-- Every stock function counts as "native" for debug.info, exactly like real C closures
for _, name in ipairs({ "pcall", "error", "tostring", "type", "select", "rawget", "setmetatable", "print" }) do
    natives[_G[name]] = true
end
debug.info = function(fn, what)
    if natives[fn] then return "[C]" end
    return "Script.lua"
end
game.HttpGet = native(game.HttpGet)

local rawLoad = load
loadstring = native(function(src, name)
    if type(src) == "string" and src:find("SCORP UI LIBRARY", 1, true) then
        H.sawRealLib = #src
        return function() return H.fakeScorp end
    end
    return rawLoad(src, name or "=payload", "t", _G)
end)
getgenv = native(function() return _G end)
gethui = native(function() return hui end)
warn = function(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    H.warnings[#H.warnings + 1] = table.concat(parts, " ")
end
local realPrint = print
print = function(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    H.prints[#H.prints + 1] = table.concat(parts, " ")
end
natives[print] = true

if env("OWNER_KEY", "") ~= "" then _G.SCORP_OWNER_KEY = env("OWNER_KEY") end

if TAMPER == "spy_global" or TAMPER == "strong" then _G.HttpSpy = true end
if TAMPER == "wrap_request" or TAMPER == "strong" then
    local orig = request
    request = function(o) return orig(o) end -- a Lua closure: debug.info says it is not native
end
if TAMPER == "strong" then
    local origPcall = pcall
    pcall = function(...) return origPcall(...) end
end

-- ───────────────────────────────────────────────────────────────────────────
--  Fake UI library (the real one needs Roblox's renderer)
-- ───────────────────────────────────────────────────────────────────────────
local theme = setmetatable({}, { __index = function() return Color3.fromRGB(200, 200, 200) end })
local function generic()
    return setmetatable({}, { __index = function(_, k)
        return function(_, ...) return generic() end
    end })
end
local Section = setmetatable({}, { __index = function(_, k)
    if k:match("^Add") then
        return function(_, name, opts)
            if type(opts) == "function" then opts = { Callback = opts } end
            H.controls[name] = opts or {}
            return generic()
        end
    end
end })
local Tab = { CreateSection = function() return Section end }
local Window = setmetatable({ Theme = theme, ToggleKey = { Name = "RightShift" }, Flags = {} }, { __index = function(_, k)
    return function(_, ...) return generic() end
end })
function Window:CreateTab() return Tab end
function Window:Notify(title, text) H.notifies[#H.notifies + 1] = tostring(title) .. ": " .. tostring(text) end
function Window:OnUnload(fn) H.unloads[#H.unloads + 1] = fn end
function Window:Destroy()
    if H.destroyed then return end
    H.destroyed = true
    for _, fn in ipairs(H.unloads) do fn() end
end
H.window = Window
H.fakeScorp = { CreateWindow = function() return Window end }

-- ───────────────────────────────────────────────────────────────────────────
--  Helpers for scenarios
-- ───────────────────────────────────────────────────────────────────────────
function H.fetchLoader()
    local res = realRequest({ Url = URL .. "/loader.lua", Method = "GET" })
    assert(res.StatusCode == 200, "loader.lua returned " .. res.StatusCode)
    return res.Body
end

function H.runLoader()
    local src = H.fetchLoader()
    H.loaderBytes = #src
    local fn, err = loadstring(src, "=loader")
    assert(fn, "loader failed to compile: " .. tostring(err))
    spawn(fn)
end

local function holderChildren()
    local folder = coreGui:FindFirstChild("ScorpTags") or hui:FindFirstChild("ScorpTags") or gui:FindFirstChild("ScorpTags")
    return folder and folder:GetChildren() or {}
end

function H.tags()
    local out = {}
    for _, g in ipairs(holderChildren()) do
        local badge = H.find(g, "Badge")
        local stroke = badge and badge:FindFirstChild("UIStroke")
        local glyph = H.find(g, "Glyph")
        local avatar = H.find(g, "Avatar")
        out[#out + 1] = {
            owner = g.Adornee and g.Adornee.Parent and g.Adornee.Parent.Name,
            title = H.find(g, "Title").Text,
            name = H.find(g, "Name").Text,
            glyph = glyph and glyph.Text,
            glyphVisible = glyph and glyph.Visible ~= false,
            avatar = avatar and avatar.Visible and avatar.Image or nil,
            accent = stroke and { stroke.Color.R, stroke.Color.G, stroke.Color.B },
            width = g.Size.X.Offset,
            maxDistance = g.MaxDistance,
            alwaysOnTop = g.AlwaysOnTop,
        }
    end
    table.sort(out, function(a, b) return tostring(a.owner) < tostring(b.owner) end)
    return out
end

function H.result(tbl)
    tbl.warnings = H.warnings
    tbl.prints = H.prints
    tbl.requests = H.requests
    tbl.threadErrors = H.threadErrors or 0
    tbl.sawRealLib = H.sawRealLib
    tbl.destroyed = H.destroyed or false
    tbl.notifies = H.notifies
    io.write("RESULT " .. json.encode(tbl) .. "\n")
end

local scenario = arg[1]
assert(scenario, "usage: texlua harness.lua <scenario.lua>")
dofile(scenario)(H)
