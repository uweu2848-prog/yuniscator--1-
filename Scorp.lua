--[[
    Scorp
    Standalone hub. Misc holds the real features (movement, world, ESP,
    hitbox, players, camera, extra, staff). Home / Player / Visuals stay
    placeholders. Nametags are not part of this file.
]]

--  Whitelist / blacklist + anti-tamper gate
-- ───────────────────────────────────────────────────────────────────────────
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Replace this with your actual Railway or deployed server URL
local API_URL = "https://sliver-surfer-test-production.up.railway.app"

-- Executor-specific request function
local http_request = (request or syn and syn.request or http and http.request)

local function getHWID()
    local success, result = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    return success and result or "UNKNOWN_HWID"
end

local headers = {
    ["X-User-ID"] = tostring(LocalPlayer.UserId),
    ["X-HWID"] = getHWID()
}

local function reportTamper(reason)
    if not http_request then return end

    -- Send silent request to backend
    pcall(function()
        local payload = HttpService:JSONEncode({
            userId = tostring(LocalPlayer.UserId),
            username = LocalPlayer.Name,
            hwid = getHWID(),
            reason = reason
        })
        http_request({
            Url = API_URL .. "/api/tamper",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = payload
        })
    end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Anti-tamper detection
--  Each check has an opaque code + a weight. Only the codes are sent to the
--  server, so nothing readable shows up in a spy log.
--
--    C1  core Lua functions (pcall, error, tostring...) replaced by Lua closures
--    H1  the executor's request function is a Lua wrapper instead of native
--    H2  request / loadstring reference changed since the script started
--    H3  game.HttpGet replaced by a Lua wrapper
--    M1  game's __namecall / __index metamethods hooked with Lua closures
--    G1  a GUI named like an HTTP spy is sitting in CoreGui / gethui()
--
--  Score = sum of weights. Start with BLOCK_SCORE = math.huge (report only),
--  watch your logs for false positives on the executors you support, then
--  lower it.
-- ───────────────────────────────────────────────────────────────────────────
local REPORT_SCORE    = 1          -- report to /api/tamper at or above this
local BLOCK_SCORE     = math.huge  -- refuse to load locally at or above this (try 3 once tuned)
local HEARTBEAT_EVERY = 60         -- seconds between re-checks / revocation checks

local SESSION_ID = HttpService:GenerateGUID(false)
local capturedRequest, capturedLoadstring = http_request, loadstring

local SPY_NAMES = { "httpspy", "http spy", "simplespy", "hookspy", "networkspy" }  -- extend as you find more

-- True if fn is a native / C closure. Returns true when it can't tell (avoids false positives).
local function isNative(fn)
    if type(fn) ~= "function" then return false end
    local ok, src = pcall(debug.info, fn, "s")
    if ok and type(src) == "string" then return src == "[C]" end
    if islclosure then
        local ok2, isL = pcall(islclosure, fn)
        if ok2 then return not isL end
    end
    return true
end

local function guiHasSpy(container)
    local ok, kids = pcall(function() return container:GetChildren() end)
    if not ok then return false end
    for _, c in ipairs(kids) do
        local n = c.Name:lower()
        for _, bad in ipairs(SPY_NAMES) do
            if n:find(bad, 1, true) then return true end
        end
    end
    return false
end

local function runChecks()
    local hits, score = {}, 0
    local function hit(code, weight)
        hits[#hits + 1] = code
        score = score + weight
    end

    -- C1: core functions should be native
    local core = { pcall, error, tostring, type, select, rawget, setmetatable, print, warn }
    for _, fn in ipairs(core) do
        if not isNative(fn) then hit("C1", 2) break end
    end

    -- H1: request function should be native (weight 1: some executors wrap it legitimately)
    if http_request and not isNative(http_request) then hit("H1", 1) end

    -- H2: request / loadstring swapped after we started
    local nowRequest = (request or syn and syn.request or http and http.request)
    if nowRequest ~= capturedRequest or loadstring ~= capturedLoadstring then hit("H2", 3) end

    -- H3: HttpGet wrapper
    local okHG, httpGet = pcall(function() return game.HttpGet end)
    if okHG and httpGet and not isNative(httpGet) then hit("H3", 1) end

    -- M1: metamethod hooks on game
    if getrawmetatable then
        local okMT, mt = pcall(getrawmetatable, game)
        if okMT and type(mt) == "table" then
            for _, m in ipairs({ "__namecall", "__index" }) do
                local f = rawget(mt, m)
                if f and not isNative(f) then hit("M1", 1) break end
            end
        end
    end

    -- G1: known spy GUIs
    local okCG, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if (okCG and guiHasSpy(coreGui)) or (gethui and guiHasSpy(gethui())) then hit("G1", 2) end

    return hits, score
end

-- Report each distinct set of findings once per session
local reported = {}
local function reportHits(hits, score)
    local key = table.concat(hits, ",")
    if key == "" or reported[key] then return end
    reported[key] = true
    reportTamper(("codes=%s score=%d session=%s"):format(key, score, SESSION_ID))
end

local function startHub()
local function loadLib()
    local src = [=[
--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║                    SCORP UI LIBRARY  v1.1.0                          ║
    ║   Chrome / cosmic UI: windows, tabs, sections, toggles, sliders,     ║
    ║   dropdowns, keybinds, color pickers, notifications, live theming,   ║
    ║   config saving, and a twinkling starfield.                          ║
    ║   Forked from the Yunīku UI library.                                 ║
    ╚══════════════════════════════════════════════════════════════════════╝

    USAGE
        local Scorp = loadstring(game:HttpGet("YOUR_RAW_URL/ScorpLib.lua"))()

        local Window = Scorp:CreateWindow({
            Title     = "SCORP",
            Theme     = "Silver Surfer",
            ToggleKey = Enum.KeyCode.RightShift,
        })

        local Tab     = Window:CreateTab("Main", { Icon = "🏄" })
        local Section = Tab:CreateSection("Combat", true)

        Section:AddToggle("Enabled", { Default = false, Flag = "enabled", Callback = function(v) end })
        Section:AddSlider("Speed",   { Min = 16, Max = 100, Default = 16, Callback = function(v) end })

    See Scorp.lua for a full placeholder hub.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local CoreGui          = game:GetService("CoreGui")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")
local TextService      = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

-- Executor globals (all optional – the library degrades gracefully without them)
local gethui       = gethui
local syn_protect  = syn and syn.protect_gui
local writefile, readfile, isfile = writefile, readfile, isfile
local isfolder, makefolder, listfiles = isfolder, makefolder, listfiles

local Library = { Version = "1.1.0" }
shared.ScorpUIWindows = shared.ScorpUIWindows or {}

-- ═══════════════════════════════════════════════════════════════════════════
--  THEMES
-- ═══════════════════════════════════════════════════════════════════════════
local BASE = {
    MainBg    = Color3.fromRGB(13, 17, 34),
    SidebarBg = Color3.fromRGB(9, 12, 26),
    ToggleOff = Color3.fromRGB(24, 30, 50),
    TextWhite = Color3.fromRGB(240, 245, 255),
    TextDim   = Color3.fromRGB(138, 152, 182),
    Success   = Color3.fromRGB(80, 230, 170),
    Danger    = Color3.fromRGB(255, 90, 110),
    Warning   = Color3.fromRGB(255, 205, 90),
}

-- Accent      = main chrome colour (borders, sliders, toggles)
-- AccentLight = the "Power Cosmic" glow that trails the chrome sheen
Library.Themes = {
    -- House theme: sharper chrome + hot violet-cyan streak, distinct from the plain "Silver Surfer" preset.
    ["Nova Silver"]   = { Accent = Color3.fromRGB(196, 206, 230), AccentLight = Color3.fromRGB(150, 120, 255),
                          MainBg = Color3.fromRGB(10, 11, 22), SidebarBg = Color3.fromRGB(7, 8, 17), ToggleOff = Color3.fromRGB(20, 21, 38) },
    ["Silver Surfer"] = { Accent = Color3.fromRGB(168, 186, 214), AccentLight = Color3.fromRGB(90, 210, 255) },
    ["Power Cosmic"]  = { Accent = Color3.fromRGB(70, 150, 255),  AccentLight = Color3.fromRGB(176, 110, 255),
                          MainBg = Color3.fromRGB(14, 12, 38), SidebarBg = Color3.fromRGB(10, 9, 28), ToggleOff = Color3.fromRGB(28, 24, 56) },
    ["Zenn-La"]       = { Accent = Color3.fromRGB(64, 196, 186),  AccentLight = Color3.fromRGB(255, 214, 120),
                          MainBg = Color3.fromRGB(8, 22, 30), SidebarBg = Color3.fromRGB(6, 16, 23), ToggleOff = Color3.fromRGB(18, 38, 48) },
    ["Deep Space"]    = { Accent = Color3.fromRGB(122, 132, 152), AccentLight = Color3.fromRGB(205, 214, 232),
                          MainBg = Color3.fromRGB(12, 13, 17), SidebarBg = Color3.fromRGB(8, 9, 12), ToggleOff = Color3.fromRGB(26, 28, 36) },
    -- Flat shell: near-black surfaces, one blue accent, hairline outline.
    ["Rayfield"] = {
        Accent = Color3.fromRGB(80, 105, 255), AccentLight = Color3.fromRGB(140, 156, 255),
        MainBg = Color3.fromRGB(15, 15, 19), SidebarBg = Color3.fromRGB(8, 8, 10),
        ToggleOff = Color3.fromRGB(26, 26, 32), TextWhite = Color3.fromRGB(237, 237, 242),
        TextDim = Color3.fromRGB(139, 139, 147), Danger = Color3.fromRGB(235, 76, 76),
        Stroke = Color3.fromRGB(46, 46, 54),
    },
}
Library.ThemeOrder = { "Rayfield", "Nova Silver", "Silver Surfer", "Power Cosmic", "Zenn-La", "Deep Space" }

--- Add your own preset: Library:RegisterTheme("Sunset", { Accent = Color3.fromRGB(255,120,40) })
function Library:RegisterTheme(name, preset)
    if not self.Themes[name] then table.insert(self.ThemeOrder, name) end
    self.Themes[name] = preset
end

local RainbowSeq = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 0, 0)),
})

-- Brushed-chrome sweep: deep space → accent → white-hot core → cosmic glow → deep space
local function Sheen(c, glow)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0,    Color3.fromRGB(14, 18, 36)),
        ColorSequenceKeypoint.new(0.38, c),
        ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.62, glow or c),
        ColorSequenceKeypoint.new(1,    Color3.fromRGB(14, 18, 36)),
    })
end

local function Brighten(c, amt)
    return Color3.fromRGB(
        math.clamp(math.floor(c.R * 255) + amt, 0, 255),
        math.clamp(math.floor(c.G * 255) + amt, 0, 255),
        math.clamp(math.floor(c.B * 255) + amt, 0, 255))
end

local function BuildTheme(preset)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    for k, v in pairs(preset) do t[k] = v end
    t.AccentLight = preset.AccentLight or Brighten(t.Accent, 60)
    return t
end

-- ═══════════════════════════════════════════════════════════════════════════
--  UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════
local function Make(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    if parent then inst.Parent = parent end
    return inst
end

local function Tween(obj, props, time, style, dir)
    local tw = TweenService:Create(obj,
        TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function Corner(parent, r)
    return Make("UICorner", { Parent = parent, CornerRadius = UDim.new(0, r or 8) })
end

local function Round(parent)
    return Make("UICorner", { Parent = parent, CornerRadius = UDim.new(1, 0) })
end

local function Fire(cb, ...)
    if type(cb) ~= "function" then return end
    local ok, err = pcall(cb, ...)
    if not ok then warn("[Scorp UI] Callback error: " .. tostring(err)) end
end

local function Pointer(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        local inset = GuiService:GetGuiInset()
        return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
    end
    return UserInputService:GetMouseLocation()
end

local function IsPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function IsMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function AttachGui(gui)
    if syn_protect then pcall(syn_protect, gui) end
    local root
    if gethui then
        local ok, r = pcall(gethui)
        if ok and r then root = r end
    end
    root = root or CoreGui
    local ok = pcall(function() gui.Parent = root end)
    if not ok or gui.Parent ~= root then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function EncodeFlag(v)
    if typeof(v) == "Color3" then
        return { __t = "c", v = string.format("%02X%02X%02X", math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255)) }
    elseif typeof(v) == "EnumItem" then
        return { __t = "k", v = v.Name }
    end
    return v
end

local function DecodeFlag(v)
    if type(v) == "table" then
        if v.__t == "c" then return Color3.fromHex(v.v)
        elseif v.__t == "k" then return Enum.KeyCode[v.v] end
    end
    return v
end

-- ═══════════════════════════════════════════════════════════════════════════
--  CLASSES
-- ═══════════════════════════════════════════════════════════════════════════
local Window  = {}; Window.__index  = Window
local Tab     = {}; Tab.__index     = Tab
local Section = {}; Section.__index = Section

-- ───────────────────────────────────────────────────────────────────────────
--  Window internals
-- ───────────────────────────────────────────────────────────────────────────
function Window:_connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self._conns, c)
    return c
end

--- Register a function that re-styles something whenever the theme changes.
function Window:_bind(fn)
    table.insert(self._binds, fn)
    pcall(fn, self.Theme)
end

function Window:_seq()
    return self.Rainbow and RainbowSeq or Sheen(self.Theme.Accent, self.Theme.AccentLight)
end

function Window:_breathe(grad)
    table.insert(self._breathing, grad)
    grad.Color = self:_seq()
    -- The sliding highlight along the border is a looping TweenService yoyo now,
    -- not a per-frame sin() calculation shared across every breathing border in the UI.
    local function Step(dir)
        if not grad.Parent then return end
        Tween(grad, { Offset = Vector2.new(dir * 1.2, 0) }, 1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(function() Step(-dir) end)
    end
    Step(1)
end

--- The signature animated gradient border.
function Window:_stroke(parent, thickness, transparency)
    local s = Make("UIStroke", {
        Parent = parent, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = self.Flat and (self.Theme.Stroke or self.Theme.Accent) or Color3.new(1, 1, 1),
        Thickness = thickness or 1, Transparency = self.Flat and 0.35 or (transparency or 0.2),
    })
    if self.Flat then
        self:_bind(function(t) s.Color = t.Stroke or t.Accent end)
    else
        self:_breathe(Make("UIGradient", { Parent = s, Rotation = 0 }))
    end
    return s
end

--- The brand glyph: a bright head with a tapered comet-tail streak, drawn with plain
-- Frames (no image asset needed). Reused in the sidebar logo, the watermark, and
-- notification accents so the whole UI shares one recognizable mark.
function Window:_cometMark(parent, size, anchor, position)
    if self.Flat then
        local d = math.max(6, math.floor((size or 14) * 0.5))
        local dot = Make("Frame", {
            Parent = parent, Size = UDim2.fromOffset(d, d), BorderSizePixel = 0,
            BackgroundColor3 = self.Theme.Accent, AnchorPoint = anchor, Position = position,
        })
        Round(dot)
        self:_bind(function(t) dot.BackgroundColor3 = t.Accent end)
        return dot
    end
    size = size or 14
    local holder = Make("Frame", { Parent = parent, Size = UDim2.fromOffset(size * 2.6, size), BackgroundTransparency = 1, AnchorPoint = anchor, Position = position })
    local tail = Make("Frame", {
        Parent = holder, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, size * 1.7, 0, math.max(2, math.floor(size * 0.16))), BorderSizePixel = 0,
    })
    Round(tail)
    Make("UIGradient", { Parent = tail, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) }) })
    local head = Make("Frame", {
        Parent = holder, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(size, size), BorderSizePixel = 0,
    })
    Round(head)
    local headStroke = Make("UIStroke", { Parent = head, Thickness = 2, Transparency = 0.45 })
    local headScale = Make("UIScale", { Parent = head, Scale = 1 })
    self:_bind(function(t)
        tail.BackgroundColor3 = t.Accent
        head.BackgroundColor3 = t.AccentLight
        headStroke.Color = t.AccentLight
    end)
    -- Gentle looping pulse, TweenService-driven like everything else in the backdrop.
    local rng = Random.new()
    local function Pulse()
        if not head.Parent then return end
        Tween(headScale, { Scale = rng:NextNumber(0.85, 1.2) }, rng:NextNumber(1.2, 2.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(Pulse)
    end
    Pulse()
    return holder
end

function Window:_play(kind)
    local s = self._sounds[kind]
    if s then pcall(function() s:Play() end) end
end

--- Hover grow + fade effect for buttons.
function Window:_fx(btn, o)
    o = o or {}
    local scale = Make("UIScale", { Parent = btn, Scale = 1 })
    local base = btn.BackgroundTransparency
    btn.MouseEnter:Connect(function()
        self:_play("Hover")
        if not self.Flat then
            Tween(scale, { Scale = o.Grow or 1.04 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        end
        if not o.NoFade then Tween(btn, { BackgroundTransparency = math.max(base - 0.2, 0) }, 0.2) end
    end)
    btn.MouseLeave:Connect(function()
        Tween(scale, { Scale = 1 }, 0.2)
        if not o.NoFade then Tween(btn, { BackgroundTransparency = base }, 0.2) end
    end)
    return scale
end

function Window:_drag(handle, target, onClick)
    local dragging, moved, startInput, startPos
    handle.InputBegan:Connect(function(input)
        if IsPress(input) then
            dragging, moved = true, false
            startInput, startPos = input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onClick and not moved then onClick() end
                end
            end)
        end
    end)
    self:_connect(UserInputService.InputChanged, function(input)
        if dragging and IsMove(input) then
            local d = input.Position - startInput
            if d.Magnitude > 5 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
end

function Window:_applyTheme()
    for _, fn in ipairs(self._binds) do pcall(fn, self.Theme) end
    local seq = self:_seq()
    for _, g in ipairs(self._breathing) do
        if g.Parent then g.Color = seq end
    end
end

-- ───────────────────────────────────────────────────────────────────────────
--  Create window
-- ───────────────────────────────────────────────────────────────────────────
--[[
    opts:
        Title          string   – logo text in the sidebar                      ("SCORP")
        Subtitle       string   – (optional) small text under the logo
        Theme          string|table   – preset name or { Accent = Color3 }     ("Silver Surfer")
        Size           UDim2    – must use offsets                             (850 x 550)
        MinSize        Vector2  – resize limits                                (700 x 450)
        MaxSize        Vector2                                                 (1200 x 800)
        ToggleKey      KeyCode  – show/hide the window                         (RightShift)
        UnloadKey      KeyCode|false – destroy the UI                          (Delete, false = disabled)
        Blur           boolean  – background blur while open                   (true)
        BlurSize       number                                                  (15)
        ToggleWidget   boolean  – floating draggable open button               (true)
        WidgetText     string
        UnloadButton   boolean  – "Unload GUI" quick action in sidebar         (true)
        StartHidden    boolean
        Starfield      boolean  – twinkling stars behind the content            (true)
        StarCount      number                                                  (80)
        Nebula         boolean  – soft glow blobs behind the content            (true)
        BackgroundImage           string – rbxassetid:// for key art behind the starfield
        BackgroundImageTransparency number – 0 (opaque) to 1 (invisible)        (0.45)
        ConfigFolder   string   – folder used by Save/LoadConfig
        Sounds         table    – { Click = "rbxassetid://..", Hover = "rbxassetid://.." }
]]
function Library:CreateWindow(opts)
    opts = opts or {}
    local self = setmetatable({}, Window)

    self.Title        = opts.Title or "SCORP"
    self.Flags        = {}
    self._setters     = {}
    self._conns       = {}
    self._binds       = {}
    self._breathing   = {}
    self._tabs        = {}
    self._onUnload    = {}
    self._quick       = {}
    self._sounds      = {}
    self.Rainbow      = false
    self.Visible      = false
    self.ToggleKey    = opts.ToggleKey or Enum.KeyCode.RightShift
    self.UnloadKey    = (opts.UnloadKey == nil) and Enum.KeyCode.Delete or (opts.UnloadKey or nil)
    self.BlurSize     = opts.BlurSize or 15
    self.ConfigFolder = opts.ConfigFolder or ("Scorp_" .. self.Title:gsub("[^%w_]", ""))

    -- Theme
    local preset
    if type(opts.Theme) == "table" then
        preset = opts.Theme; self.ThemeName = opts.Theme.Name or "Custom"
    else
        self.ThemeName = Library.Themes[opts.Theme or ""] and opts.Theme or "Nova Silver"
        preset = Library.Themes[self.ThemeName]
    end
    self.Theme = BuildTheme(preset)
    self.Flat = opts.Flat == true

    -- Replace an existing instance of the same window
    local guiName = "ScorpUI_" .. self.Title:gsub("[^%w_]", "")
    local old = shared.ScorpUIWindows[guiName]
    if old then pcall(function() old:Destroy(true) end) end
    shared.ScorpUIWindows[guiName] = self
    self._id = guiName

    self.Gui = Make("ScreenGui", {
        Name = guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    AttachGui(self.Gui)

    if opts.Blur ~= false then
        self.Blur = Make("BlurEffect", { Name = guiName .. "_Blur", Size = 0, Parent = Lighting })
    end

    for kind, id in pairs(opts.Sounds or {}) do
        self._sounds[kind] = Make("Sound", { Parent = self.Gui, SoundId = id, Volume = kind == "Click" and 0.6 or 0.3 })
    end

    -- ── Main frame ──
    local size = opts.Size or UDim2.fromOffset(850, 550)
    local minSize = opts.MinSize or Vector2.new(700, 450)
    local maxSize = opts.MaxSize or Vector2.new(1200, 800)

    self.Main = Make("Frame", {
        Name = "MainWindow", Parent = self.Gui, Size = size,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 0.05, ClipsDescendants = true, Active = true, Visible = false,
    })
    self._mainScale = Make("UIScale", { Parent = self.Main, Scale = 0 })
    Corner(self.Main, self.Flat and 10 or 14)
    if not self.Flat then
        Make("UIGradient", { Parent = self.Main, Rotation = -45, Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(205, 215, 255)),
            ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 238, 255)),
        }) })
    end
    self.mainStroke = Make("UIStroke", { Parent = self.Main, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = self.Flat and 1 or 2, Transparency = 0.15 })
    self:_bind(function(t) self.Main.BackgroundColor3 = t.MainBg; self.mainStroke.Color = t.Stroke or t.Accent end)

    -- ── Cosmic backdrop: nebula glow, twinkling stars, shooting stars ──
    if opts.Starfield ~= false then
        local field = Make("Frame", { Name = "Starfield", Parent = self.Main, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
        local rng = Random.new(1966)

        -- Optional backdrop art (e.g. the Silver Surfer key art) behind the stars/nebula.
        -- Must be an rbxassetid:// — Roblox ImageLabels can't play an animated .gif directly.
        if opts.BackgroundImage then
            local bg = Make("ImageLabel", {
                Name = "BackgroundArt", Parent = field, Size = UDim2.fromScale(1.16, 1.16),
                Position = UDim2.fromScale(-0.08, -0.08), BackgroundTransparency = 1,
                Image = opts.BackgroundImage, ImageTransparency = opts.BackgroundImageTransparency or 0.45,
                ScaleType = Enum.ScaleType.Crop,
            })
            local bgScale = Make("UIScale", { Parent = bg, Scale = 1 })
            local function BgDrift() -- slow Ken-Burns style zoom, TweenService-driven
                if not bg.Parent then return end
                Tween(bgScale, { Scale = rng:NextNumber(1, 1.07) }, rng:NextNumber(9, 14), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(BgDrift)
            end
            BgDrift()
        end

        -- Soft glows faked with stacked translucent discs (no image assets needed).
        -- Each glow "orb" drifts slowly and breathes in/out — both driven by TweenService
        -- (a looping tween per orb) rather than per-frame math, so it stays smooth and cheap.
        if opts.Nebula ~= false then
            local function Glow(cx, cy, radius, layers)
                local anchor = Make("Frame", {
                    Parent = field, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy),
                    Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1,
                })
                local scaler = Make("UIScale", { Parent = anchor, Scale = 1 })
                local list = {}
                for i = 1, layers do
                    local r = radius * (1 - (i - 1) / layers)
                    local f = Make("Frame", {
                        Parent = anchor, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                        Size = UDim2.fromOffset(r * 2, r * 2), BackgroundTransparency = 0.98, BorderSizePixel = 0,
                    })
                    Round(f)
                    list[i] = f
                end

                local function Drift()
                    if not anchor.Parent then return end
                    local dx, dy = rng:NextNumber(-22, 22), rng:NextNumber(-16, 16)
                    local goal = UDim2.fromScale(cx, cy) + UDim2.fromOffset(dx, dy)
                    Tween(anchor, { Position = goal }, rng:NextNumber(5, 8), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(Drift)
                end
                local function Breathe()
                    if not anchor.Parent then return end
                    Tween(scaler, { Scale = rng:NextNumber(0.82, 1.18) }, rng:NextNumber(3.5, 5.5), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(Breathe)
                end
                Drift()
                Breathe()
                return list
            end
            local glowA = Glow(0.95, 0.04, 280, 12)
            local glowB = Glow(0.30, 1.05, 320, 12)
            self:_bind(function(t)
                for _, f in ipairs(glowA) do f.BackgroundColor3 = t.AccentLight end
                for _, f in ipairs(glowB) do f.BackgroundColor3 = t.Accent end
            end)
        end

        -- Twinkle is a looping TweenService tween per star (staggered start + random duration)
        -- instead of a manual Heartbeat/sin calculation over every star every frame.
        local function Twinkle(star)
            local function Step()
                if not star.Parent then return end
                local target = rng:NextNumber(0.15, 0.9)
                local dur = rng:NextNumber(0.6, 2.4)
                Tween(star, { BackgroundTransparency = target }, dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(Step)
            end
            task.delay(rng:NextNumber(0, 2), Step) -- stagger so stars don't all pulse in sync
        end

        for i = 1, (opts.StarCount or 80) do
            local px = (i % 9 == 0) and 3 or rng:NextInteger(1, 2)
            local s = Make("Frame", {
                Parent = field, BorderSizePixel = 0, Size = UDim2.fromOffset(px, px),
                Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), BackgroundTransparency = 0.6,
                BackgroundColor3 = (i % 5 == 0) and Color3.fromRGB(150, 225, 255) or Color3.new(1, 1, 1),
            })
            if px > 1 then Round(s) end
            Twinkle(s)
        end

        local function Shoot()
            local w, h = self.Main.Size.X.Offset, self.Main.Size.Y.Offset
            local ang = math.rad(28)
            local dist = rng:NextInteger(220, 320)
            local sx, sy = rng:NextNumber(0.25, 0.95) * w, rng:NextNumber(0, 0.4) * h
            local streak = Make("Frame", {
                Parent = field, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx, sy),
                Size = UDim2.fromOffset(rng:NextInteger(70, 130), 2), Rotation = 28, BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.05,
            })
            Round(streak)
            Make("UIGradient", { Parent = streak, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) })
            Tween(streak, { Position = UDim2.fromOffset(sx + math.cos(ang) * dist, sy + math.sin(ang) * dist), BackgroundTransparency = 1 }, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.delay(1, function() streak:Destroy() end)
        end

        -- Shooting stars are scheduled on their own recursive delay loop (no per-frame polling needed).
        local function ScheduleShoot()
            task.delay(rng:NextNumber(5, 11), function()
                if self.Visible then Shoot() end
                ScheduleShoot()
            end)
        end
        ScheduleShoot()
    end

    -- ── Sidebar ──
    self.Sidebar = Make("Frame", { Parent = self.Main, Size = UDim2.new(0, 190, 1, 0), BackgroundTransparency = 0.2, BorderSizePixel = 0 })
    self:_bind(function(t) self.Sidebar.BackgroundColor3 = t.SidebarBg end)
    if not self.Flat then
        Make("UIGradient", { Parent = self.Sidebar, Rotation = 90, Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 185, 225)) }) })
    end
    local edge = Make("Frame", { Parent = self.Sidebar, Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    if not self.Flat then
        Make("UIGradient", { Parent = edge, Rotation = 90, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }) })
    end
    self:_bind(function(t) edge.BackgroundColor3 = self.Flat and (t.Stroke or t.Accent) or t.Accent end)

    -- Subtitle gets its own generous, word-wrapped block instead of a single clipped line.
    local subtitleBlockHeight = 0
    if opts.Subtitle then
        local lines = math.ceil(#opts.Subtitle / 26) -- rough chars-per-line estimate at TextSize 10 / 150px width
        subtitleBlockHeight = math.max(28, lines * 13 + 6)
    end
    local markRow = 20 -- room for the comet brand mark above the wordmark
    local logoArea = Make("Frame", { Parent = self.Sidebar, Size = UDim2.new(1, 0, 0, markRow + 40 + subtitleBlockHeight + (opts.Subtitle and 10 or 6)), BackgroundTransparency = 1, Active = true })
    self:_cometMark(logoArea, 12, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4))
    local logo = Make("TextLabel", {
        Parent = logoArea, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, markRow), BackgroundTransparency = 1, Text = self.Title,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 28,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    if self.Flat then
        logo.TextColor3 = self.Theme.TextWhite
        self:_bind(function(t) logo.TextColor3 = t.TextWhite end)
    else
        self:_breathe(Make("UIGradient", { Parent = logo, Rotation = 0 }))
        local logoGlow = Make("UIStroke", { Parent = logo, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 1.5, Transparency = 0.72 })
        self:_bind(function(t) logoGlow.Color = t.AccentLight end)
    end
    if opts.Subtitle then
        Make("TextLabel", {
            Parent = logoArea, Size = UDim2.new(1, -20, 0, subtitleBlockHeight), Position = UDim2.new(0, 10, 0, markRow + 40),
            BackgroundTransparency = 1, Text = opts.Subtitle, TextColor3 = self.Theme.TextDim,
            Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
        })
    end
    local logoLine = Make("Frame", { Parent = logoArea, Size = UDim2.new(1, -40, 0, self.Flat and 1 or 2), Position = UDim2.new(0, 20, 1, -2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    if self.Flat then
        self:_bind(function(t) logoLine.BackgroundColor3 = t.Stroke or t.Accent end)
    else
        local divGrad = Make("UIGradient", { Parent = logoLine, Rotation = 0, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.7) }) })
        self:_breathe(divGrad)
        local diamondGlow = Make("Frame", { Parent = logoArea, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(16, 16), Rotation = 45, BackgroundTransparency = 0.82, BorderSizePixel = 0 })
        Corner(diamondGlow, 3)
        Make("Frame", { Parent = logoArea, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(7, 7), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
        self:_bind(function(t) diamondGlow.BackgroundColor3 = t.AccentLight end)
    end

    local searchY = logoArea.Size.Y.Offset + 10
    local searchBg = Make("Frame", { Parent = self.Sidebar, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, searchY), BackgroundTransparency = 0.5, ClipsDescendants = false })
    Corner(searchBg, 6)
    self:_bind(function(t) searchBg.BackgroundColor3 = t.ToggleOff end)
    local searchStroke = Make("UIStroke", { Parent = searchBg, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.7 })
    self:_cometMark(searchBg, 8, Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0))
    local searchBox = Make("TextBox", {
        Parent = searchBg, Size = UDim2.new(1, -36, 1, 0), Position = UDim2.new(0, 32, 0, 0), BackgroundTransparency = 1,
        Text = "", PlaceholderText = "Search tabs...", TextColor3 = self.Theme.TextWhite, PlaceholderColor3 = self.Theme.TextDim,
        Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
    })
    searchBox.Focused:Connect(function()
        Tween(searchBg, { BackgroundTransparency = 0.2 }, 0.2)
        Tween(searchStroke, { Transparency = 0.2, Color = self.Theme.Accent }, 0.2)
    end)
    searchBox.FocusLost:Connect(function()
        Tween(searchBg, { BackgroundTransparency = 0.5 }, 0.2)
        Tween(searchStroke, { Transparency = 0.7, Color = Color3.new(1, 1, 1) }, 0.2)
    end)

    -- Typing effect: every character added (letters, numbers, symbols — anything) kicks off a
    -- tiny spark at the cursor position and a quick brightness pulse on the box border.
    local lastLen = 0
    local function TypeSpark()
        local textW = TextService:GetTextSize(searchBox.Text, 11, Enum.Font.GothamBold, Vector2.new(1000, 20)).X
        local sparkX = math.clamp(32 + textW, 32, searchBg.AbsoluteSize.X - 6)
        local spark = Make("Frame", {
            Parent = searchBg, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, sparkX, 0.5, 0),
            Size = UDim2.fromOffset(4, 4), BackgroundColor3 = self.Theme.AccentLight, BorderSizePixel = 0, ZIndex = 5,
        })
        Round(spark)
        Tween(spark, { Position = UDim2.new(0, sparkX, 0, -5), Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1 },
            0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Connect(function() spark:Destroy() end)
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local text = searchBox.Text
        if #text > lastLen then
            Tween(searchStroke, { Transparency = 0 }, 0.05)
            task.delay(0.05, function() if searchBox:IsFocused() then Tween(searchStroke, { Transparency = 0.2 }, 0.25) end end)
            TypeSpark()
        end
        lastLen = #text
        local q = text:lower():match("^%s*(.-)%s*$")
        for _, t in ipairs(self._tabs) do
            t._btn.Visible = (q == "") or (t.Name:lower():find(q, 1, true) ~= nil)
        end
    end)

    self._tabTop = searchY + 40
    self._tabList = Make("ScrollingFrame", {
        Parent = self.Sidebar, Size = UDim2.new(1, 0, 1, -self._tabTop), Position = UDim2.new(0, 0, 0, self._tabTop),
        BackgroundTransparency = 1, ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(), ClipsDescendants = true, BorderSizePixel = 0,
    })
    Make("UIListLayout", { Parent = self._tabList, Padding = UDim.new(0, 4) })
    Make("UIPadding", { Parent = self._tabList, PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 15) })

    self._footer = Make("Frame", { Parent = self.Sidebar, Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Visible = false })
    local footLine = Make("Frame", { Parent = self._footer, Size = UDim2.new(1, -40, 0, self.Flat and 1 or 2), Position = UDim2.new(0, 20, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    if self.Flat then
        self:_bind(function(t) footLine.BackgroundColor3 = t.Stroke or t.Accent end)
    else
        self:_breathe(Make("UIGradient", { Parent = footLine, Rotation = 0, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.8) }) }))
    end
    Make("TextLabel", {
        Parent = self._footer, Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 0, 8), BackgroundTransparency = 1,
        Text = "QUICK ACTIONS", TextColor3 = self.Theme.TextDim, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    })

    -- ── Content area ──
    self.Content = Make("Frame", { Parent = self.Main, Size = UDim2.new(1, -190, 1, 0), Position = UDim2.new(0, 190, 0, 0), BackgroundTransparency = 1 })
    local topStrip = Make("Frame", { Parent = self.Content, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Active = true })
    self._hint = Make("TextLabel", {
        Parent = topStrip, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1,
        TextColor3 = self.Theme.TextDim, Font = Enum.Font.Montserrat, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
    })
    self._pageTitle = Make("TextLabel", {
        Parent = topStrip, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 26, 0, 0), BackgroundTransparency = 1,
        Text = "", TextColor3 = self.Theme.TextWhite, Font = Enum.Font.GothamBlack, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
    })
    self._pages = Make("Frame", { Parent = self.Content, Size = UDim2.new(1, 0, 1, -40), Position = UDim2.new(0, 0, 0, 40), BackgroundTransparency = 1 })

    self:_drag(logoArea, self.Main)
    self:_drag(topStrip, self.Main)

    -- Resize handle
    local rh = Make("TextButton", {
        Parent = self.Main, Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1,
        Text = "◢", Font = Enum.Font.GothamBold, TextSize = 16, ZIndex = 100, AutoButtonColor = false,
    })
    self:_bind(function(t) rh.TextColor3 = t.Accent end)
    do
        local resizing, rs, ss, sp
        rh.InputBegan:Connect(function(input)
            if IsPress(input) then
                resizing, rs = true, input.Position
                ss = Vector2.new(self.Main.Size.X.Offset, self.Main.Size.Y.Offset)
                sp = self.Main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then resizing = false end
                end)
            end
        end)
        self:_connect(UserInputService.InputChanged, function(input)
            if resizing and IsMove(input) then
                local d = input.Position - rs
                local w = math.clamp(ss.X + d.X, minSize.X, maxSize.X)
                local h = math.clamp(ss.Y + d.Y, minSize.Y, maxSize.Y)
                self.Main.Size = UDim2.fromOffset(w, h)
                -- keep the top-left corner fixed (window is center-anchored)
                self.Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + (w - ss.X) / 2, sp.Y.Scale, sp.Y.Offset + (h - ss.Y) / 2)
            end
        end)
    end

    -- ── Notifications ──
    self._notifs = Make("Frame", { Parent = self.Gui, Size = UDim2.new(0, 300, 1, 0), Position = UDim2.new(1, -315, 0, 0), BackgroundTransparency = 1, ZIndex = 200 })
    Make("UIListLayout", { Parent = self._notifs, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right })
    Make("UIPadding", { Parent = self._notifs, PaddingBottom = UDim.new(0, 70), PaddingRight = UDim.new(0, 15) })

    -- ── Floating toggle widget ──
    if opts.ToggleWidget ~= false then
        local w = Make("TextButton", {
            Parent = self.Gui, Size = UDim2.fromOffset(110, 40), Position = UDim2.new(0, 20, 1, -60),
            BackgroundColor3 = Color3.fromRGB(12, 16, 32), BackgroundTransparency = 0.2, Text = "", AutoButtonColor = false, ZIndex = 50,
        })
        Round(w)
        self:_stroke(w, 2, 0.2)
        local row = Make("Frame", { Parent = w, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1 })
        Make("UIListLayout", { Parent = row, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) })
        self:_cometMark(row, 10)
        Make("TextLabel", {
            Parent = row, Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1,
            Text = (opts.WidgetText or self.Title):upper(), TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBlack, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
        })
        local ws = Make("UIScale", { Parent = w, Scale = 0 })
        w.MouseEnter:Connect(function() self:_play("Hover"); Tween(ws, { Scale = 1.05 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
        w.MouseLeave:Connect(function() Tween(ws, { Scale = 1 }, 0.15) end)
        self:_drag(w, w, function() self:_play("Click"); self:Toggle() end)
        Tween(ws, { Scale = 1 }, 0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        self._widget = w
        self._widgetScale = ws
        w.Visible = not self.Visible -- only needed to *reopen* a closed panel; see Toggle() below
    end

    -- ── Global keys ──
    self:_connect(UserInputService.InputBegan, function(input, gp)
        if gp or self._binding then return end
        if input.KeyCode == self.ToggleKey then
            self:Toggle()
        elseif self.UnloadKey and input.KeyCode == self.UnloadKey then
            self:Destroy()
        end
    end)

    self:_updateHint()

    if opts.UnloadButton ~= false then
        self:AddQuickAction("Unload GUI", function() self:Destroy() end, BASE.Danger)
    end

    if not opts.StartHidden then self:Toggle(true) end
    return self
end

-- ───────────────────────────────────────────────────────────────────────────
--  Window public API
-- ───────────────────────────────────────────────────────────────────────────
function Window:_updateHint()
    local txt = "[" .. self.ToggleKey.Name .. "] Toggle"
    if self.UnloadKey then txt = txt .. "  |  [" .. self.UnloadKey.Name .. "] Unload" end
    self._hint.Text = txt
end

function Window:SetToggleKey(key)
    self.ToggleKey = key
    self:_updateHint()
end

function Window:Toggle(state)
    if self.Destroyed then return end
    if state == nil then state = not self.Visible end
    self.Visible = state
    -- The floating widget only exists to reopen a *closed* panel. Left visible while the
    -- panel is open, it sits at a fixed screen corner with a high ZIndex and — whenever the
    -- open panel's sidebar/tabs/buttons happen to overlap that corner — silently swallows
    -- clicks meant for them (a click-without-drag on the widget calls Toggle(), closing the
    -- panel). Hiding it while open removes the conflict entirely.
    if self._widget then
        if state then
            Tween(self._widgetScale, { Scale = 0 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In).Completed:Connect(function()
                if self.Visible then self._widget.Visible = false end
            end)
        else
            self._widget.Visible = true
            Tween(self._widgetScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        end
    end

    if state then
        self.Main.Visible = true
        if self.Blur then Tween(self.Blur, { Size = self.BlurSize }, 0.35) end
        Tween(self._mainScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

        -- Border flashes bright on every open, and the very first open gets a one-time
        -- power-on sweep — the closest a mounted GUI gets to a branded loading beat.
        if self.mainStroke then
            local baseTransparency = self.mainStroke.Transparency
            self.mainStroke.Transparency = 0
            Tween(self.mainStroke, { Transparency = baseTransparency }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end
        if not self._booted then
            self._booted = true
            local sweep = Make("Frame", {
                Parent = self.Main, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 0, 0),
                BackgroundColor3 = self.Theme.AccentLight, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 50,
            })
            Tween(sweep, { Position = UDim2.new(0, 0, 1, -3), BackgroundTransparency = 1 }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                .Completed:Connect(function() sweep:Destroy() end)
        end
    else
        if self.Blur then Tween(self.Blur, { Size = 0 }, 0.3) end
        Tween(self._mainScale, { Scale = 0 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.3, function()
            if not self.Visible and self.Main then self.Main.Visible = false end
        end)
    end
end

function Window:OnUnload(fn)
    table.insert(self._onUnload, fn)
end

function Window:Destroy(instant)
    if self.Destroyed then return end
    self.Destroyed = true
    for _, fn in ipairs(self._onUnload) do Fire(fn) end
    for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    if shared.ScorpUIWindows[self._id] == self then shared.ScorpUIWindows[self._id] = nil end

    local function finish()
        pcall(function() self.Gui:Destroy() end)
        if self.Blur then pcall(function() self.Blur:Destroy() end) end
    end
    if instant then return finish() end
    Tween(self._mainScale, { Scale = 0 }, 0.3)
    if self.Blur then Tween(self.Blur, { Size = 0 }, 0.35) end
    if self._widget then Tween(self._widget:FindFirstChildOfClass("UIScale"), { Scale = 0 }, 0.3) end
    task.delay(0.4, finish)
end

--- Window:Notify("Title", "Description", 3, optionalColor)   or   Window:Notify({Title=, Content=, Duration=, Color=})
function Window:Notify(title, desc, duration, color)
    if type(title) == "table" then
        local o = title
        title, desc, duration, color = o.Title, o.Content or o.Description, o.Duration, o.Color
    end
    duration = duration or 3
    local c = color or self.Theme.Accent

    local wrapper = Make("Frame", { Parent = self._notifs, Size = UDim2.new(1, 0, 0, 65), BackgroundTransparency = 1 })
    local notif = Make("Frame", {
        Parent = wrapper, Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(1, 50, 0, 0),
        BackgroundColor3 = self.Flat and self.Theme.MainBg or Color3.fromRGB(14, 18, 36), BackgroundTransparency = 0.2,
    })
    local notifScale = Make("UIScale", { Parent = notif, Scale = 0.85 })
    Corner(notif, self.Flat and 8 or 10)
    local stroke = Make("UIStroke", { Parent = notif, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = self.Flat and (self.Theme.Stroke or c) or c, Thickness = self.Flat and 1 or 2, Transparency = 0.2 })
    if self.Flat then
        self:_bind(function(t) notif.BackgroundColor3 = t.MainBg; if not color then stroke.Color = t.Stroke or t.Accent end end)
    elseif not color then
        self:_breathe(Make("UIGradient", { Parent = stroke, Rotation = 0 }))
    end

    if color or self.Flat then
        -- Explicit color (e.g. success/danger) keeps a plain accent bar so the color reads instantly.
        local bar = Make("Frame", { Parent = notif, Size = UDim2.new(0, 4, 1, -20), Position = UDim2.new(0, 10, 0, 10), BackgroundColor3 = c, BorderSizePixel = 0 })
        Round(bar)
    else
        -- Default notifications carry the brand comet mark instead of a plain bar.
        self:_cometMark(notif, 12, Vector2.new(0, 0.5), UDim2.new(0, 12, 0, 20))
    end
    Make("TextLabel", {
        Parent = notif, Size = UDim2.new(1, -30, 0, 20), Position = UDim2.new(0, 25, 0, 10), BackgroundTransparency = 1,
        Text = tostring(title or ""), TextColor3 = self.Theme.TextWhite, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
    })
    Make("TextLabel", {
        Parent = notif, Size = UDim2.new(1, -30, 0, 30), Position = UDim2.new(0, 25, 0, 30), BackgroundTransparency = 1,
        Text = tostring(desc or ""), TextColor3 = self.Theme.TextDim, Font = Enum.Font.Montserrat, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
    })

    self:_play("Click")
    Tween(notif, { Position = UDim2.new(0, 0, 0, 0) }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    Tween(notifScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    task.delay(duration, function()
        if not notif.Parent then return end
        Tween(notifScale, { Scale = 0.9 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        local tw = Tween(notif, { Position = UDim2.new(1, 50, 0, 0), BackgroundTransparency = 1 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        tw.Completed:Wait()
        wrapper:Destroy()
    end)
end

--- Bottom-right pill, supports RichText. Pass nil/"" to hide.
function Window:SetWatermark(text)
    if not self._wm then
        self._wm = Make("Frame", {
            Parent = self.Gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20),
            AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 30),
            BackgroundColor3 = Color3.fromRGB(10, 13, 28), BackgroundTransparency = 0.35, ZIndex = 60,
        })
        Corner(self._wm, 8)
        self:_stroke(self._wm, 1.5, 0.2)
        local list = Make("UIListLayout", { Parent = self._wm, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) })
        Make("UIPadding", { Parent = self._wm, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) })
        self:_cometMark(self._wm, 9)
        self._wmText = Make("TextLabel", {
            Parent = self._wm, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
            TextColor3 = self.Theme.TextWhite, Font = Enum.Font.Montserrat, TextSize = 13, RichText = true,
        })
    end
    self._wmText.Text = text or ""
    self._wm.Visible = text ~= nil and text ~= ""
end

-- ── Theming ──
--- Window:SetTheme("Cyberpunk")  |  Window:SetTheme(Color3.fromRGB(...))  |  Window:SetTheme({Accent=..., MainBg=...})
function Window:SetTheme(theme)
    local preset, name
    if type(theme) == "string" then
        preset, name = Library.Themes[theme], theme
    elseif typeof(theme) == "Color3" then
        preset, name = { Accent = theme }, "Custom"
    elseif type(theme) == "table" then
        preset, name = theme, theme.Name or "Custom"
    end
    if not preset then return false end
    self.Rainbow = false
    self.ThemeName = name
    self.Theme = BuildTheme(preset)
    self:_applyTheme()
    return true
end

function Window:SetRainbow(state)
    self.Rainbow = state and true or false
    if self.Rainbow then self.ThemeName = "Rainbow RGB" end
    self:_applyTheme()
end

--- Adds a ready-made "Theme" section (preset dropdown, accent picker, rainbow toggle) to a tab.
function Window:AddThemeControls(tab, title)
    local sec = tab:CreateSection(title or "🎨 Theme", true)
    local accent
    sec:AddDropdown("Preset:", {
        Options = Library.ThemeOrder, Default = self.ThemeName,
        Callback = function(v)
            self:SetTheme(v)
            if accent then accent:Set(self.Theme.Accent, true) end
        end,
    })
    accent = sec:AddColorPicker("Accent Color", {
        Default = self.Theme.Accent,
        Callback = function(c) self:SetTheme(c) end,
    })
    sec:AddToggle("Rainbow RGB", { Bindable = false, Callback = function(v) self:SetRainbow(v) end })
    return sec
end

-- ── Config saving (needs executor file functions) ──
function Window:SaveConfig(name)
    if not (writefile and makefolder and isfolder) then return false, "executor has no file functions" end
    name = (name and name ~= "") and name or "default"
    pcall(function() if not isfolder(self.ConfigFolder) then makefolder(self.ConfigFolder) end end)
    local data = {}
    for k, v in pairs(self.Flags) do data[k] = EncodeFlag(v) end
    local ok, err = pcall(function()
        writefile(self.ConfigFolder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
    return ok, err
end

function Window:LoadConfig(name)
    if not (readfile and isfile) then return false, "executor has no file functions" end
    local path = self.ConfigFolder .. "/" .. tostring(name) .. ".json"
    if not isfile(path) then return false, "config not found" end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok then return false, "config is corrupted" end
    for flag, raw in pairs(data) do
        local setter = self._setters[flag]
        if setter then pcall(setter, DecodeFlag(raw)) end
    end
    return true
end

function Window:ListConfigs()
    local out = {}
    if listfiles and isfolder and isfolder(self.ConfigFolder) then
        pcall(function()
            for _, p in ipairs(listfiles(self.ConfigFolder)) do
                local n = p:match("([^/\\]+)%.json$")
                if n then table.insert(out, n) end
            end
        end)
    end
    return out
end

--- Adds a ready-made "Configs" section (name box, save, load, list) to a tab.
function Window:AddConfigControls(tab, title)
    local sec = tab:CreateSection(title or "💾 Configs", false)
    local nameBox = sec:AddTextbox("Config name", { Default = "default", Placeholder = "name..." })
    local list
    sec:AddButton("Save Config", function()
        local ok, err = self:SaveConfig(nameBox:Get())
        self:Notify(ok and "Config Saved" or "Save Failed", ok and nameBox:Get() or tostring(err), 3, ok and self.Theme.Success or self.Theme.Danger)
        if ok and list then list:Refresh(self:ListConfigs()) end
    end)
    list = sec:AddDropdown("Saved:", { Options = self:ListConfigs(), Callback = function(v) nameBox:Set(v, true) end })
    sec:AddButton("Load Config", function()
        local ok, err = self:LoadConfig(nameBox:Get())
        self:Notify(ok and "Config Loaded" or "Load Failed", ok and nameBox:Get() or tostring(err), 3, ok and self.Theme.Success or self.Theme.Danger)
    end)
    return sec
end

-- ── Sidebar quick actions ──
function Window:AddQuickAction(text, callback, textColor)
    local n = #self._quick + 1
    local btn = Make("TextButton", {
        Parent = self._footer, Size = UDim2.new(1, -40, 0, 32), Position = UDim2.new(0, 20, 0, 32 + (n - 1) * 40),
        BackgroundTransparency = 0.3, Text = text, TextColor3 = textColor or self.Theme.TextDim,
        Font = Enum.Font.Montserrat, TextSize = 12, AutoButtonColor = false,
    })
    self:_bind(function(t) btn.BackgroundColor3 = t.ToggleOff end)
    Corner(btn, 8)
    self:_stroke(btn, 1, 0.2)
    self:_fx(btn, { Grow = 1.05 })
    btn.MouseButton1Click:Connect(function() self:_play("Click"); Fire(callback) end)
    self._quick[n] = btn

    local h = 32 + n * 40
    self._footer.Visible = true
    self._footer.Size = UDim2.new(1, 0, 0, h)
    self._footer.Position = UDim2.new(0, 0, 1, -h)
    self._tabList.Size = UDim2.new(1, 0, 1, -(self._tabTop + h))
    return btn
end

-- ───────────────────────────────────────────────────────────────────────────
--  Tabs
-- ───────────────────────────────────────────────────────────────────────────
function Window:SelectTab(tab)
    for _, t in ipairs(self._tabs) do
        if t == tab then
            Tween(t._fg, { TextColor3 = self.Flat and Color3.new(1, 1, 1) or self.Theme.TextWhite }, 0.2)
            Tween(t._txtStroke, { Transparency = self.Flat and 1 or 0.3 }, 0.2)
            t._indicator.Visible = not self.Flat
            t._pill.Visible = true
            t._pill.BackgroundTransparency = self.Flat and 0 or 1
            Tween(t._pill, { BackgroundTransparency = self.Flat and 0 or 0.86 }, 0.3)
            t.Page.Visible = true
            t._pageScale.Scale = 0.96
            Tween(t._pageScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        else
            Tween(t._fg, { TextColor3 = self.Theme.TextDim }, 0.2)
            Tween(t._txtStroke, { Transparency = 0.75 }, 0.2)
            t._indicator.Visible = false
            t._pill.Visible = false
            t.Page.Visible = false
        end
    end
    self.CurrentTab = tab
    if self._pageTitle then self._pageTitle.Text = tab.Name:upper() end
end

--- opts: { Icon = "🏠", Default = true }
function Window:CreateTab(name, opts)
    opts = opts or {}
    local tab = setmetatable({ Window = self, Name = name }, Tab)
    local label = "      " .. (opts.Icon and (opts.Icon .. "  ") or "") .. name
    local isDefault = opts.Default or (#self._tabs == 0)

    local btn = Make("TextButton", { Parent = self._tabList, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Text = "", AutoButtonColor = false })
    local pill = Make("Frame", { Parent = btn, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 0.86, BorderSizePixel = 0, Visible = false })
    Corner(pill, 8)
    self:_stroke(pill, 1, 0.55)
    self:_bind(function(t) pill.BackgroundColor3 = t.Accent end)
    local bgText = Make("TextLabel", {
        Parent = btn, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = label, TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.Montserrat, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 1,
    })
    local txtStroke = Make("UIStroke", { Parent = bgText, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = self.Flat and 1 or 0.75 })
    if not self.Flat then self:_breathe(Make("UIGradient", { Parent = txtStroke, Rotation = 0 })) end
    local fgText = Make("TextLabel", {
        Parent = btn, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = label, TextColor3 = self.Theme.TextDim,
        Font = Enum.Font.Montserrat, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
    })
    local btnScale = Make("UIScale", { Parent = btn, Scale = 1 })
    -- Active-tab marker is the same comet glyph used everywhere else, not a plain bar.
    local indicator = self:_cometMark(btn, 8, Vector2.new(0, 0.5), UDim2.new(0, 6, 0.5, 0))
    indicator.Visible = false

    local page = Make("ScrollingFrame", {
        Parent = self._pages, Size = UDim2.new(1, -12, 1, -6), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1,
        Visible = false, BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    })
    self:_bind(function(t) page.ScrollBarImageColor3 = t.Accent end)
    local pageScale = Make("UIScale", { Parent = page, Scale = 1 })
    Make("UIPadding", { Parent = page, PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 25), PaddingBottom = UDim.new(0, 25) })
    Make("UIListLayout", { Parent = page, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })

    tab.Page, tab._btn, tab._fg, tab._txtStroke, tab._indicator, tab._pageScale = page, btn, fgText, txtStroke, indicator, pageScale
    tab._pill = pill
    table.insert(self._tabs, tab)

    btn.MouseEnter:Connect(function()
        self:_play("Hover")
        local active = (self.Flat and self.CurrentTab == tab) or indicator.Visible
        if not active then
            Tween(fgText, { TextColor3 = self.Theme.TextWhite }, 0.15)
            if not self.Flat then Tween(txtStroke, { Transparency = 0.45 }, 0.15) end
        end
        if not self.Flat then
            Tween(btnScale, { Scale = 1.05 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            Tween(bgText, { Position = UDim2.new(0, 8, 0, 0) }, 0.25, Enum.EasingStyle.Quint)
            Tween(fgText, { Position = UDim2.new(0, 8, 0, 0) }, 0.25, Enum.EasingStyle.Quint)
        end
    end)
    btn.MouseLeave:Connect(function()
        local active = (self.Flat and self.CurrentTab == tab) or indicator.Visible
        if not active then
            Tween(fgText, { TextColor3 = self.Theme.TextDim }, 0.15)
            if not self.Flat then Tween(txtStroke, { Transparency = 0.75 }, 0.15) end
        end
        if not self.Flat then
            Tween(btnScale, { Scale = 1 }, 0.2)
            Tween(bgText, { Position = UDim2.new() }, 0.25, Enum.EasingStyle.Quint)
            Tween(fgText, { Position = UDim2.new() }, 0.25, Enum.EasingStyle.Quint)
        end
    end)
    btn.MouseButton1Click:Connect(function()
        self:_play("Click")
        if not self.Flat then
            Tween(btnScale, { Scale = 0.95 }, 0.1)
            task.delay(0.1, function() Tween(btnScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
        end
        self:SelectTab(tab)
    end)

    if isDefault then self:SelectTab(tab) end
    return tab
end

-- ───────────────────────────────────────────────────────────────────────────
--  Sections
-- ───────────────────────────────────────────────────────────────────────────
function Tab:CreateSection(title, expanded)
    local win = self.Window
    expanded = expanded ~= false
    local SH = 32

    local wrapper = Make("Frame", { Parent = self.Page, Size = UDim2.new(1, 0, 0, SH), BackgroundTransparency = 1, ClipsDescendants = true })
    local header = Make("TextButton", { Parent = wrapper, Size = UDim2.new(1, 0, 0, SH), BackgroundTransparency = 0.3, Text = "", AutoButtonColor = false })
    win:_bind(function(t) header.BackgroundColor3 = t.ToggleOff end)
    Corner(header, 6)
    win:_stroke(header, 1, 0.5)
    if not win.Flat then
        Make("UIGradient", { Parent = header, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }) })
        win:_cometMark(header, 9, Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0))
    end
    Make("TextLabel", {
        Parent = header, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, win.Flat and 12 or 28, 0, 0), BackgroundTransparency = 1,
        Text = win.Flat and string.upper(title) or title, TextColor3 = win.Flat and win.Theme.TextDim or win.Theme.TextWhite,
        Font = Enum.Font.GothamBold, TextSize = win.Flat and 11 or 13, TextXAlignment = Enum.TextXAlignment.Left,
    })
    -- Arrow rotates (tweened) instead of swapping glyphs, so it stays in line with the tween-only rule.
    local arrow = Make("TextLabel", {
        Parent = header, Size = UDim2.new(0, 20, 1, 0), Position = UDim2.new(1, -25, 0, 0), BackgroundTransparency = 1,
        Text = "▶", Font = Enum.Font.GothamBold, TextSize = 12, Rotation = expanded and 90 or 0,
    })
    win:_bind(function(t) arrow.TextColor3 = t.Accent end)

    local content = Make("Frame", { Parent = wrapper, Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, SH + 6), BackgroundTransparency = 1, ClipsDescendants = true })
    local layout = Make("UIListLayout", { Parent = content, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
    Make("UIPadding", { Parent = content, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) })

    local function resize(animate)
        local ch = layout.AbsoluteContentSize.Y + 4
        local wh = expanded and (SH + 6 + ch) or SH
        local cH = expanded and ch or 0
        local rot = expanded and 90 or 0
        if animate then
            Tween(wrapper, { Size = UDim2.new(1, 0, 0, wh) }, 0.35, Enum.EasingStyle.Quint)
            Tween(content, { Size = UDim2.new(1, 0, 0, cH) }, 0.35, Enum.EasingStyle.Quint)
            Tween(arrow, { Rotation = rot }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        else
            wrapper.Size = UDim2.new(1, 0, 0, wh)
            content.Size = UDim2.new(1, 0, 0, cH)
            arrow.Rotation = rot
        end
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if expanded then resize(false) end
    end)
    header.MouseEnter:Connect(function() win:_play("Hover"); Tween(header, { BackgroundTransparency = 0.1 }, 0.2) end)
    header.MouseLeave:Connect(function() Tween(header, { BackgroundTransparency = 0.3 }, 0.2) end)
    header.MouseButton1Click:Connect(function() win:_play("Click"); expanded = not expanded; resize(true) end)
    task.defer(resize, false)

    local sec = setmetatable({ Window = win, Tab = self, Content = content, Wrapper = wrapper }, Section)
    function sec:SetExpanded(v) expanded = v and true or false; resize(true) end
    return sec
end

-- ───────────────────────────────────────────────────────────────────────────
--  Elements
-- ───────────────────────────────────────────────────────────────────────────
local function Row(section, height)
    return Make("Frame", { Parent = section.Content, Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1 })
end

local function RowLabel(win, parent, text, widthOffset)
    return Make("TextLabel", {
        Parent = parent, Size = UDim2.new(1, widthOffset or -120, 1, 0), BackgroundTransparency = 1, Text = text,
        TextColor3 = win.Theme.TextWhite, Font = Enum.Font.Montserrat, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local function Register(win, flag, obj, getter)
    if not flag then return end
    win.Flags[flag] = getter()
    win._setters[flag] = function(v) obj:Set(v) end
end

--- Section:AddLabel("text", { TextSize = 13, Color = Color3, Wrap = true })  → { Set(text) }
function Section:AddLabel(text, o)
    o = o or {}
    local win = self.Window
    local lbl = Make("TextLabel", {
        Parent = self.Content, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = text,
        TextColor3 = o.Color or win.Theme.TextWhite, Font = Enum.Font.Montserrat, TextSize = o.TextSize or 13,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = o.Wrap or false,
        AutomaticSize = o.Wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
    })
    local obj = { Frame = lbl }
    function obj:Set(t) lbl.Text = t end
    function obj:SetColor(c) lbl.TextColor3 = c end
    return obj
end

--- Section:AddCustom(height) -> Frame
--- An empty transparent row you can build anything into (the tag editor's live preview lives in one).
function Section:AddCustom(height)
    return Make("Frame", { Parent = self.Content, Size = UDim2.new(1, 0, 0, height or 100), BackgroundTransparency = 1, ClipsDescendants = true })
end

--- Section:AddButton("Name", function() end)
function Section:AddButton(name, callback)
    local win = self.Window
    local btn = Make("TextButton", {
        Parent = self.Content, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 0.3, Text = name,
        TextColor3 = win.Theme.TextWhite, Font = Enum.Font.Montserrat, TextSize = 13, AutoButtonColor = false,
    })
    win:_bind(function(t) btn.BackgroundColor3 = t.ToggleOff end)
    Corner(btn, 8)
    if not win.Flat then
        Make("UIGradient", { Parent = btn, Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 235)) })
    end
    win:_stroke(btn, 1, 0.2)
    local scale = win:_fx(btn, { Grow = 1.04 })
    if not win.Flat then
        btn.MouseButton1Down:Connect(function() Tween(scale, { Scale = 0.94 }, 0.1) end)
        btn.MouseButton1Up:Connect(function() Tween(scale, { Scale = 1.04 }, 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
    end
    btn.MouseButton1Click:Connect(function()
        win:_play("Click")
        Tween(btn, { BackgroundColor3 = win.Theme.Accent, BackgroundTransparency = 0 }, 0.1)
        task.delay(0.2, function()
            if btn.Parent then Tween(btn, { BackgroundColor3 = win.Theme.ToggleOff, BackgroundTransparency = 0.3 }, 0.2) end
        end)
        Fire(callback)
    end)
    local obj = { Frame = btn }
    function obj:SetText(t) btn.Text = t end
    return obj
end

-- Small "[ KEY ]" rebinding button used by toggles and keybinds
local function BindButton(win, parent, pos, size, default, onChange)
    local key = default
    local btn = Make("TextButton", {
        Parent = parent, Size = size, Position = pos, BackgroundTransparency = 0.5,
        Text = key and ("[ " .. key.Name .. " ]") or "[ None ]", TextColor3 = win.Theme.TextDim,
        Font = Enum.Font.Code, TextSize = 11, AutoButtonColor = false,
    })
    win:_bind(function(t) btn.BackgroundColor3 = t.ToggleOff end)
    Corner(btn, 4)
    local stroke = Make("UIStroke", { Parent = btn, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.5 })

    local binding = false
    local api = {}
    function api.Get() return key end
    function api.Set(k, silent)
        key = k
        btn.Text = k and ("[ " .. k.Name .. " ]") or "[ None ]"
        if not silent then Fire(onChange, k) end
    end
    btn.MouseButton1Click:Connect(function()
        win:_play("Click")
        binding = true
        win._binding = true
        btn.Text = "[ ... ]"
        Tween(stroke, { Transparency = 0, Color = win.Theme.Accent }, 0.2)
    end)
    win:_connect(UserInputService.InputBegan, function(input)
        if binding and input.UserInputType == Enum.UserInputType.Keyboard then
            binding = false
            task.defer(function() win._binding = false end)
            if input.KeyCode == Enum.KeyCode.Escape then api.Set(nil) else api.Set(input.KeyCode) end
            Tween(stroke, { Transparency = 0.5, Color = Color3.new(1, 1, 1) }, 0.2)
        end
    end)
    return api, btn
end

--[[ Section:AddToggle("Name", {
        Default  = false,
        Flag     = "myFlag",           -- enables config save/load + Window.Flags.myFlag
        Bindable = true,               -- show the [ None ] keybind button (default true)
        Keybind  = Enum.KeyCode.X,     -- default key
        Callback = function(state) end,
    })  → { Set(bool), Get() }
]]
function Section:AddToggle(name, o)
    if type(o) == "function" then o = { Callback = o } end
    o = o or {}
    local win = self.Window
    local state = o.Default == true
    local bindable = o.Bindable ~= false

    local row = Row(self, 32)
    RowLabel(win, row, name, bindable and -120 or -60)

    local switch = Make("TextButton", { Parent = row, Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0.5, -12), Text = "", AutoButtonColor = false })
    Corner(switch, 12)
    win:_stroke(switch, 1, 0.2)
    local knob = Make("Frame", { Parent = switch, Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(248, 248, 250), Position = UDim2.new(0, 2, 0.5, -10) })
    Round(knob)
    -- Soft glow ring that only shows up when the toggle is on, so "on" reads as more than a color swap.
    local knobGlow = Make("UIStroke", { Parent = knob, Thickness = 4, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
    win:_bind(function(t) knobGlow.Color = t.AccentLight end)
    win:_fx(switch, { Grow = 1.1, NoFade = true })

    local obj = { Frame = row }
    local function render(instant)
        local t = win.Theme
        local props = { BackgroundColor3 = state and t.Accent or t.ToggleOff, BackgroundTransparency = state and 0 or 0.3 }
        local kp = { Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10) }
        local gp = { Transparency = state and 0.45 or 1 }
        if instant then
            for k, v in pairs(props) do switch[k] = v end
            knob.Position = kp.Position
            knobGlow.Transparency = gp.Transparency
        else
            Tween(switch, props, 0.25)
            Tween(knob, kp, 0.25)
            Tween(knobGlow, gp, 0.25)
        end
    end
    win:_bind(function() render(true) end)

    function obj:Set(v, silent)
        state = v and true or false
        if o.Flag then win.Flags[o.Flag] = state end
        render(false)
        if not silent then Fire(o.Callback, state) end
    end
    function obj:Get() return state end
    switch.MouseButton1Click:Connect(function() win:_play("Click"); obj:Set(not state) end)
    Register(win, o.Flag, obj, function() return state end)

    if bindable then
        local bind = BindButton(win, row, UDim2.new(1, -112, 0.5, -10), UDim2.fromOffset(60, 20), o.Keybind, function(k)
            if o.Flag then win.Flags[o.Flag .. "_Key"] = k end
        end)
        if o.Flag then
            win.Flags[o.Flag .. "_Key"] = o.Keybind
            win._setters[o.Flag .. "_Key"] = function(k) bind.Set(k, true); win.Flags[o.Flag .. "_Key"] = k end
        end
        win:_connect(UserInputService.InputBegan, function(input, gp)
            local k = bind.Get()
            if win._binding or gp or not k or input.KeyCode ~= k then return end
            obj:Set(not state)
            if o.KeybindNotify ~= false then
                win:Notify("Keybind Triggered", name .. (state and " Enabled" or " Disabled"), 2, state and win.Theme.Success or win.Theme.Danger)
            end
        end)
        function obj:SetKey(k) bind.Set(k) end
    end
    return obj
end

--[[ Section:AddSlider("Name", { Min=0, Max=100, Default=50, Increment=1, Suffix="%", Flag=, Callback= })  → { Set(n), Get() } ]]
function Section:AddSlider(name, o)
    o = o or {}
    local win = self.Window
    local min, max = o.Min or 0, o.Max or 100
    local inc = o.Increment or 1
    local dec = 0
    local frac = tostring(inc):match("%.(%d+)")
    if frac then dec = #frac end
    local value = math.clamp(o.Default or min, min, max)

    local row = Row(self, 44)
    local nameLbl = Make("TextLabel", {
        Parent = row, Size = UDim2.new(1, -80, 0, 20), BackgroundTransparency = 1, Text = name, TextColor3 = win.Theme.TextWhite,
        Font = Enum.Font.Montserrat, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local valLbl = Make("TextLabel", {
        Parent = row, Size = UDim2.new(0, 80, 0, 20), Position = UDim2.new(1, -80, 0, 0), BackgroundTransparency = 1,
        TextColor3 = win.Theme.TextDim, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
    })
    local track = Make("Frame", { Parent = row, Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 28), BackgroundTransparency = 0.3, Active = true })
    win:_bind(function(t) track.BackgroundColor3 = t.ToggleOff end)
    Round(track)
    win:_stroke(track, 1, 0.2)
    local fill = Make("Frame", { Parent = track, Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 })
    Round(fill)
    if win.Flat then
        fill.BackgroundColor3 = win.Theme.Accent
        win:_bind(function(t) fill.BackgroundColor3 = t.Accent end)
    else
        fill.BackgroundColor3 = Color3.new(1, 1, 1)
        local fillGrad = Make("UIGradient", { Parent = fill })
        win:_bind(function(t) fillGrad.Color = ColorSequence.new(t.Accent, t.AccentLight) end)
    end
    local knob = Make("Frame", { Parent = track, Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.new(0, -6, 0.5, -6) })
    Round(knob)
    -- Glow ring that brightens while actively dragging, echoing the toggle's on-glow.
    local knobGlow = Make("UIStroke", { Parent = knob, Thickness = 3, Transparency = 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
    win:_bind(function(t) knobGlow.Color = t.AccentLight end)

    local obj = { Frame = row }
    local function render()
        local a = (max == min) and 0 or (value - min) / (max - min)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, -6, 0.5, -6)
        valLbl.Text = tostring(value) .. (o.Suffix or "")
    end
    function obj:Set(v, silent)
        v = math.clamp(tonumber(v) or min, min, max)
        v = math.floor((v - min) / inc + 0.5) * inc + min
        value = tonumber(string.format("%." .. dec .. "f", math.clamp(v, min, max)))
        if o.Flag then win.Flags[o.Flag] = value end
        render()
        if not silent then Fire(o.Callback, value) end
    end
    function obj:Get() return value end

    local dragging = false
    local function fromInput(input)
        local a = math.clamp((Pointer(input).X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        obj:Set(min + (max - min) * a)
    end
    track.InputBegan:Connect(function(input) if IsPress(input) then dragging = true; Tween(knobGlow, { Transparency = 0.15 }, 0.15); fromInput(input) end end)
    win:_connect(UserInputService.InputEnded, function(input) if IsPress(input) then dragging = false; Tween(knobGlow, { Transparency = 0.75 }, 0.25) end end)
    win:_connect(UserInputService.InputChanged, function(input) if dragging and IsMove(input) then fromInput(input) end end)

    render()
    Register(win, o.Flag, obj, function() return value end)
    if o.Callback and o.CallOnCreate then Fire(o.Callback, value) end
    return obj
end

--[[ Section:AddDropdown("Name:", { Options = {"A","B"}, Default = "A", Flag=, Callback = function(v) end })
     → { Set(v), Get(), Refresh(newOptions) } ]]
function Section:AddDropdown(name, o)
    o = o or {}
    local win = self.Window
    local options = o.Options or {}
    local current = o.Default
    local HEAD, OPT_H, MAX_VISIBLE = 32, 28, 6
    local isOpen = false

    local container = Make("Frame", { Parent = self.Content, Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, ClipsDescendants = true })
    Make("TextLabel", {
        Parent = container, Size = UDim2.new(0.35, 0, 0, HEAD), BackgroundTransparency = 1, Text = " " .. name,
        TextColor3 = win.Theme.TextDim, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local btn = Make("TextButton", {
        Parent = container, Size = UDim2.new(0.65, 0, 0, HEAD - 4), Position = UDim2.new(0.35, 0, 0, 2), BackgroundTransparency = 0.3,
        Text = "", AutoButtonColor = false,
    })
    win:_bind(function(t) btn.BackgroundColor3 = t.ToggleOff end)
    Corner(btn, 6)
    win:_stroke(btn, 1, 0.4)
    local btnLabel = Make("TextLabel", {
        Parent = btn, Size = UDim2.new(1, -26, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
        TextColor3 = win.Theme.TextWhite, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    -- Rotates open/closed (tweened) instead of swapping ▲/▼ glyphs.
    local btnArrow = Make("TextLabel", { Parent = btn, Size = UDim2.new(0, 16, 1, 0), Position = UDim2.new(1, -20, 0, 0), BackgroundTransparency = 1, Text = "▶", Font = Enum.Font.GothamBold, TextSize = 10 })
    win:_bind(function(t) btnArrow.TextColor3 = t.Accent end)

    local list = Make("ScrollingFrame", {
        Parent = container, Position = UDim2.new(0.35, 0, 0, HEAD + 2), BackgroundColor3 = Color3.fromRGB(14, 18, 36), BackgroundTransparency = 0.1,
        BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    })
    Corner(list, 6)
    local listStroke = Make("UIStroke", { Parent = list, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = 0.4 })
    win:_bind(function(t) listStroke.Color = t.Accent; list.ScrollBarImageColor3 = t.Accent end)
    Make("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })

    local obj = { Frame = container }
    local build -- forward declare so updateText/Set can refresh the highlighted row
    local function updateText()
        btnLabel.Text = current ~= nil and tostring(current) or "Select..."
    end
    local function openHeight()
        return HEAD + math.min(#options, MAX_VISIBLE) * OPT_H + 8
    end
    local function setOpen(v)
        isOpen = v
        Tween(btnArrow, { Rotation = v and 90 or 0 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        Tween(container, { Size = UDim2.new(1, 0, 0, v and openHeight() or HEAD) }, v and 0.35 or 0.25, Enum.EasingStyle.Quint)
    end

    function build()
        for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        list.Size = UDim2.new(0.65, 0, 0, math.min(#options, MAX_VISIBLE) * OPT_H)
        for i, opt in ipairs(options) do
            local isSelected = (opt == current)
            local ob = Make("TextButton", {
                Parent = list, Size = UDim2.new(1, 0, 0, OPT_H), BackgroundTransparency = isSelected and 0.85 or 1, LayoutOrder = i, Text = tostring(opt),
                TextColor3 = isSelected and win.Theme.TextWhite or win.Theme.TextDim,
                Font = isSelected and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = 12, AutoButtonColor = false,
            })
            win:_bind(function(t) if isSelected then ob.BackgroundColor3 = t.Accent end end)
            ob.MouseEnter:Connect(function() Tween(ob, { TextColor3 = win.Theme.TextWhite, BackgroundTransparency = 0.8 }, 0.15) end)
            ob.MouseLeave:Connect(function() Tween(ob, { TextColor3 = isSelected and win.Theme.TextWhite or win.Theme.TextDim, BackgroundTransparency = isSelected and 0.85 or 1 }, 0.15) end)
            ob.MouseButton1Click:Connect(function()
                win:_play("Click")
                obj:Set(opt)
                setOpen(false)
            end)
        end
        if isOpen then container.Size = UDim2.new(1, 0, 0, openHeight()) end
    end

    function obj:Set(v, silent)
        current = v
        if o.Flag then win.Flags[o.Flag] = v end
        updateText()
        build()
        if not silent then Fire(o.Callback, v) end
    end
    function obj:Get() return current end
    function obj:Refresh(newOptions, keepValue)
        options = newOptions or {}
        if not keepValue and current ~= nil and not table.find(options, current) then current = nil; updateText() end
        build()
    end

    btn.MouseButton1Click:Connect(function() win:_play("Click"); setOpen(not isOpen) end)
    build()
    updateText()
    Register(win, o.Flag, obj, function() return current end)
    return obj
end

--[[ Section:AddTextbox("Name", { Default="", Placeholder="", Flag=, Callback=function(text) end }) → { Set(text), Get() } ]]
function Section:AddTextbox(name, o)
    o = o or {}
    local win = self.Window
    local row = Row(self, 32)
    Make("TextLabel", {
        Parent = row, Size = UDim2.new(0.35, 0, 1, 0), BackgroundTransparency = 1, Text = " " .. name,
        TextColor3 = win.Theme.TextDim, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local bg = Make("Frame", { Parent = row, Size = UDim2.new(0.65, 0, 1, -4), Position = UDim2.new(0.35, 0, 0, 2), BackgroundTransparency = 0.3 })
    win:_bind(function(t) bg.BackgroundColor3 = t.ToggleOff end)
    Corner(bg, 6)
    local focusStroke = Make("UIStroke", { Parent = bg, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.6 })
    local box = Make("TextBox", {
        Parent = bg, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
        Text = o.Default or "", PlaceholderText = o.Placeholder or "", TextColor3 = win.Theme.TextWhite, PlaceholderColor3 = win.Theme.TextDim,
        Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
    })
    -- Border lights up to the accent color while focused, same feel as the sidebar search box.
    box.Focused:Connect(function() Tween(focusStroke, { Transparency = 0.1, Color = win.Theme.Accent }, 0.2) end)
    box.FocusLost:Connect(function() Tween(focusStroke, { Transparency = 0.6, Color = Color3.new(1, 1, 1) }, 0.2) end)
    local obj = { Frame = row }
    function obj:Set(t, silent)
        box.Text = tostring(t or "")
        if o.Flag then win.Flags[o.Flag] = box.Text end
        if not silent then Fire(o.Callback, box.Text) end
    end
    function obj:Get() return box.Text end
    box.FocusLost:Connect(function(enter)
        if o.Flag then win.Flags[o.Flag] = box.Text end
        if enter or o.CallOnBlur then Fire(o.Callback, box.Text) end
    end)
    Register(win, o.Flag, obj, function() return box.Text end)
    return obj
end

--[[ Section:AddKeybind("Name", { Default = Enum.KeyCode.F, Flag=, Callback = function() end (fires when key is pressed),
                                  OnChange = function(newKey) end }) → { Set(key), Get() } ]]
function Section:AddKeybind(name, o)
    o = o or {}
    local win = self.Window
    local row = Row(self, 32)
    RowLabel(win, row, name, -100)
    local bind
    bind = BindButton(win, row, UDim2.new(1, -80, 0.5, -12), UDim2.fromOffset(80, 24), o.Default, function(k)
        if o.Flag then win.Flags[o.Flag] = k end
        Fire(o.OnChange, k)
    end)
    local obj = { Frame = row }
    function obj:Set(k, silent) bind.Set(k, silent); if o.Flag then win.Flags[o.Flag] = k end end
    function obj:Get() return bind.Get() end
    win:_connect(UserInputService.InputBegan, function(input, gp)
        local k = bind.Get()
        if win._binding or gp or not k or input.KeyCode ~= k then return end
        Fire(o.Callback, k)
    end)
    if o.Flag then
        win.Flags[o.Flag] = o.Default
        win._setters[o.Flag] = function(k) obj:Set(k, true) end
    end
    return obj
end

--[[ Section:AddColorPicker("Name", { Default = Color3, Flag=, Callback = function(color) end }) → { Set(color), Get() }
     Click the swatch to expand an HSV picker + hex box. ]]
function Section:AddColorPicker(name, o)
    o = o or {}
    local win = self.Window
    local color = o.Default or Color3.fromRGB(255, 255, 255)
    local h, s, v = color:ToHSV()
    local HEAD, SV_H, OPEN_H = 32, 120, 194
    local isOpen = false

    local container = Make("Frame", { Parent = self.Content, Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, ClipsDescendants = true })
    local head = Make("Frame", { Parent = container, Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1 })
    RowLabel(win, head, name, -60)
    local swatch = Make("TextButton", { Parent = head, Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0.5, -12), Text = "", AutoButtonColor = false, BackgroundColor3 = color })
    Corner(swatch, 6)
    local swatchGlow = Make("UIStroke", { Parent = swatch, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 3, Transparency = 1, Color = Color3.new(1, 1, 1) })
    win:_stroke(swatch, 1, 0.2)
    win:_fx(swatch, { Grow = 1.1, NoFade = true })

    local body = Make("Frame", { Parent = container, Size = UDim2.new(1, 0, 0, OPEN_H - HEAD), Position = UDim2.new(0, 0, 0, HEAD + 4), BackgroundTransparency = 1 })
    local sv = Make("Frame", { Parent = body, Size = UDim2.new(1, -40, 0, SV_H), BackgroundColor3 = Color3.fromHSV(h, 1, 1), Active = true })
    Corner(sv, 8)
    local white = Make("Frame", { Parent = sv, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1) })
    Corner(white, 8)
    Make("UIGradient", { Parent = white, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) })
    local black = Make("Frame", { Parent = sv, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0) })
    Corner(black, 8)
    Make("UIGradient", { Parent = black, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) })
    local svKnob = Make("Frame", { Parent = sv, Size = UDim2.fromOffset(12, 12), BackgroundColor3 = color, ZIndex = 2 })
    Round(svKnob)
    Make("UIStroke", { Parent = svKnob, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(0, 0, 0), Thickness = 2 })

    local hue = Make("Frame", { Parent = body, Size = UDim2.new(0, 28, 0, SV_H), Position = UDim2.new(1, -28, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), Active = true })
    Corner(hue, 8)
    Make("UIGradient", { Parent = hue, Rotation = 90, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,     Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.167, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.333, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.5,   Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.667, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.833, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1,     Color3.fromRGB(255, 0, 0)),
    }) })
    local hueKnob = Make("Frame", { Parent = hue, Size = UDim2.new(1, -6, 0, 4), Position = UDim2.new(0, 3, 0, -2), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
    Round(hueKnob)
    Make("UIStroke", { Parent = hueKnob, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(0, 0, 0), Thickness = 2 })

    local hexBg = Make("Frame", { Parent = body, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, SV_H + 6), BackgroundTransparency = 0.3 })
    win:_bind(function(t) hexBg.BackgroundColor3 = t.ToggleOff end)
    Corner(hexBg, 6)
    local hexFocusStroke = Make("UIStroke", { Parent = hexBg, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.6 })
    local hexBox = Make("TextBox", {
        Parent = hexBg, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
        Text = "", PlaceholderText = "#FFFFFF", TextColor3 = win.Theme.TextWhite, Font = Enum.Font.Code, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
    })
    hexBox.Focused:Connect(function() Tween(hexFocusStroke, { Transparency = 0.1, Color = win.Theme.Accent }, 0.2) end)
    hexBox.FocusLost:Connect(function() Tween(hexFocusStroke, { Transparency = 0.6, Color = Color3.new(1, 1, 1) }, 0.2) end)

    local obj = { Frame = container }
    local function render()
        color = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = color
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svKnob.BackgroundColor3 = color
        svKnob.Position = UDim2.new(s, -6, 1 - v, -6)
        hueKnob.Position = UDim2.new(0, 3, h, -2)
        hexBox.Text = string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
    end
    local function commit(silent)
        render()
        if o.Flag then win.Flags[o.Flag] = color end
        if not silent then Fire(o.Callback, color) end
    end
    function obj:Set(c, silent) h, s, v = c:ToHSV(); commit(silent) end
    function obj:Get() return color end

    local draggingSV, draggingHue = false, false
    local function fromSV(input)
        local p = Pointer(input)
        s = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
        v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
        commit()
    end
    local function fromHue(input)
        h = math.clamp((Pointer(input).Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
        commit()
    end
    sv.InputBegan:Connect(function(input) if IsPress(input) then draggingSV = true; fromSV(input) end end)
    hue.InputBegan:Connect(function(input) if IsPress(input) then draggingHue = true; fromHue(input) end end)
    win:_connect(UserInputService.InputEnded, function(input) if IsPress(input) then draggingSV, draggingHue = false, false end end)
    win:_connect(UserInputService.InputChanged, function(input)
        if not IsMove(input) then return end
        if draggingSV then fromSV(input) elseif draggingHue then fromHue(input) end
    end)
    hexBox.FocusLost:Connect(function()
        local hex = hexBox.Text:match("#?(%x%x%x%x%x%x)")
        if hex then obj:Set(Color3.fromHex(hex)) else render() end
    end)
    swatch.MouseButton1Click:Connect(function()
        win:_play("Click")
        isOpen = not isOpen
        swatchGlow.Color = win.Theme.AccentLight
        Tween(swatchGlow, { Transparency = isOpen and 0.35 or 1 }, 0.25)
        Tween(container, { Size = UDim2.new(1, 0, 0, isOpen and OPEN_H or HEAD) }, 0.35, Enum.EasingStyle.Quint)
    end)

    render()
    Register(win, o.Flag, obj, function() return color end)
    return obj
end

Library.Window, Library.Tab, Library.Section = Window, Tab, Section
return Library
]=]
    local fn, err = loadstring(src)
    assert(fn, "[Scorp] UI library failed to compile: " .. tostring(err))
    local lib = fn()
    assert(lib, "[Scorp] UI library ran but returned nothing.")
    return lib
end

local Scorp = loadLib()

local Features = (function()
-- ───────────────────────────────────────────────────────────────────────────
--  Misc features (movement, visuals, players, world, staff panel).
--  Pulled into src/script.lua by the build (--@include). Lua 5.1 only.
--  Nametags are not touched here.
-- ───────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local Features = {}
local conns = {}
local alive = true
local started = false

local function connect(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function findPlayer(txt)
    txt = string.lower(tostring(txt or ""))
    if txt == "" then return nil end
    local list = Players:GetPlayers()
    for i = 1, #list do
        local p = list[i]
        if p ~= LocalPlayer then
            local name = string.lower(p.Name)
            local display = string.lower(p.DisplayName)
            if string.sub(name, 1, #txt) == txt or string.sub(display, 1, #txt) == txt then
                return p
            end
        end
    end
    return nil
end

-- ── movement ──────────────────────────────────────────────────────────────
local cframeOn = false
local cframeSpeed = 16
local noclipOn = false
local noclipParts = {}
local infJumpOn = false
local walkSpeed = 16
local jumpPower = 50
local spinOn = false
local spinSpeed = 10

function Features.SetCFrame(on) cframeOn = on and true or false end
function Features.CFrameOn() return cframeOn end
function Features.SetCFrameSpeed(n)
    n = tonumber(n) or cframeSpeed
    if n < 0 then n = 0 end
    if n > 1000000 then n = 1000000 end
    cframeSpeed = n
end

local function noclipRestore()
    for part, orig in pairs(noclipParts) do
        if part and part.Parent then part.CanCollide = orig end
    end
    noclipParts = {}
end

function Features.SetNoclip(on)
    noclipOn = on and true or false
    if not noclipOn then noclipRestore() end
end

function Features.SetInfJump(on) infJumpOn = on and true or false end

local function applyWalk()
    local hum = getHum()
    if hum then hum.WalkSpeed = walkSpeed end
end

local function applyJump()
    local hum = getHum()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = jumpPower
    end
end

function Features.SetWalkSpeed(n)
    n = tonumber(n) or walkSpeed
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    walkSpeed = n
    applyWalk()
end

function Features.SetJumpPower(n)
    n = tonumber(n) or jumpPower
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    jumpPower = n
    applyJump()
end

function Features.SetSpin(on) spinOn = on and true or false end
function Features.SetSpinSpeed(n)
    n = tonumber(n) or spinSpeed
    if n < -50 then n = -50 end
    if n > 50 then n = 50 end
    spinSpeed = n
end

-- ── fly ───────────────────────────────────────────────────────────────────
local flyOn = false
local flySpeed = 50
local flyBV, flyBG
local flyMove = { f = 0, b = 0, l = 0, r = 0 }

local function stopFly()
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    local root = getHRP()
    if root then
        local g = root:FindFirstChild("ScorpFlyGyro")
        local v = root:FindFirstChild("ScorpFlyVel")
        if g then g:Destroy() end
        if v then v:Destroy() end
    end
    flyBV, flyBG = nil, nil
    flyMove = { f = 0, b = 0, l = 0, r = 0 }
end

local function startFly()
    local root, hum = getHRP(), getHum()
    if not root or not hum then return end
    hum.PlatformStand = true
    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "ScorpFlyGyro"
    flyBG.P = 90000
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root
    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "ScorpFlyVel"
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.Parent = root
end

function Features.SetFly(on)
    flyOn = on and true or false
    if flyOn then startFly() else stopFly() end
end
function Features.FlyOn() return flyOn end
function Features.SetFlySpeed(n)
    n = tonumber(n) or flySpeed
    if n < 0 then n = 0 end
    if n > 1000000 then n = 1000000 end
    flySpeed = n
end

-- ── gravity / world ───────────────────────────────────────────────────────
local normalGravity = workspace.Gravity
if normalGravity == 0 then normalGravity = 196.2 end
local customGravity = normalGravity
local gravOn = false
local applyingGravity = false

function Features.SetGravity(on)
    gravOn = on and true or false
    applyingGravity = true
    workspace.Gravity = gravOn and customGravity or normalGravity
    applyingGravity = false
end
function Features.GravityOn() return gravOn end
function Features.SetCustomGravity(n)
    n = tonumber(n) or customGravity
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    customGravity = n
    if gravOn then
        applyingGravity = true
        workspace.Gravity = customGravity
        applyingGravity = false
    end
end

local worldOrig = nil
local fullbrightOn = false
local nofogOn = false
local xrayOn = false
local xrayParts = {}
local fov = 70
local origFov = (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70
local lockFovOn = false

local function captureLighting()
    if worldOrig then return end
    worldOrig = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
    }
end

local function applyLighting()
    captureLighting()
    if fullbrightOn then
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
    else
        Lighting.Ambient = worldOrig.Ambient
        Lighting.OutdoorAmbient = worldOrig.OutdoorAmbient
        Lighting.Brightness = worldOrig.Brightness
        Lighting.ClockTime = worldOrig.ClockTime
        Lighting.GlobalShadows = worldOrig.GlobalShadows
    end
    if nofogOn then
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
    else
        Lighting.FogEnd = worldOrig.FogEnd
        Lighting.FogStart = worldOrig.FogStart
    end
end

function Features.SetFullbright(on)
    fullbrightOn = on and true or false
    applyLighting()
end
function Features.SetNoFog(on)
    nofogOn = on and true or false
    applyLighting()
end

function Features.SetXray(on)
    xrayOn = on and true or false
    if xrayOn then
        local desc = workspace:GetDescendants()
        for i = 1, #desc do
            local p = desc[i]
            if p:IsA("BasePart") and p.Parent and not p.Parent:FindFirstChildOfClass("Humanoid") then
                if xrayParts[p] == nil then xrayParts[p] = p.LocalTransparencyModifier end
                p.LocalTransparencyModifier = 0.65
            end
        end
    else
        for p, orig in pairs(xrayParts) do
            if p and p.Parent then p.LocalTransparencyModifier = orig end
        end
        xrayParts = {}
    end
end

function Features.SetFov(n)
    n = tonumber(n) or fov
    if n < 1 then n = 1 end
    if n > 120 then n = 120 end
    fov = n
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = fov end
end
function Features.SetLockFov(on) lockFovOn = on and true or false end

local infFolder = nil
function Features.ToggleInfBaseplate()
    if infFolder and infFolder.Parent then
        infFolder:Destroy()
        infFolder = nil
        return "infbaseplate removed"
    end
    local TILE, THICK, N = 2048, 16, 8
    local bp = workspace:FindFirstChild("Baseplate") or workspace:FindFirstChild("Base") or workspace:FindFirstChild("Ground")
    if bp and not bp:IsA("BasePart") then bp = nil end
    local floorY, mat, col = 0, Enum.Material.Plastic, Color3.fromRGB(110, 110, 110)
    if bp then
        floorY = bp.Position.Y + bp.Size.Y / 2 - THICK / 2
        mat = bp.Material
        col = bp.Color
    end
    infFolder = Instance.new("Folder")
    infFolder.Name = "ScorpInfBaseplate"
    infFolder.Parent = workspace
    local parts, cframes, index = {}, {}, 1
    for x = -N, N do
        for z = -N, N do
            local p = Instance.new("Part")
            p.Anchored = true
            p.CanCollide = true
            p.Size = Vector3.new(TILE, THICK, TILE)
            p.Material = mat
            p.Color = col
            p.TopSurface = Enum.SurfaceType.Smooth
            p.BottomSurface = Enum.SurfaceType.Smooth
            parts[index] = p
            cframes[index] = CFrame.new(x * TILE, floorY, z * TILE)
            index = index + 1
        end
    end
    for i = 1, #parts do parts[i].Parent = infFolder end
    workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    return "infbaseplate placed"
end

-- ── anti-fling / air / void / invis / freecam ─────────────────────────────
local antiflingOn = false
local airOn = false
local airOffset = 3
local airPart = nil
local platOn = false
local platBV = nil
local hipValue = nil
local voidOn = false
local lastSafe = nil
local invisOn = false

function Features.SetAntifling(on) antiflingOn = on and true or false end

local function airClear()
    if airPart then airPart:Destroy() airPart = nil end
end
function Features.SetAirwalk(on)
    airOn = on and true or false
    if not airOn then airClear() end
end
function Features.SetAirOffset(n)
    n = tonumber(n) or airOffset
    if n < -50 then n = -50 end
    if n > 50 then n = 50 end
    airOffset = n
end

local function platApply()
    if platBV then platBV:Destroy() platBV = nil end
    if not platOn then return end
    local hrp = getHRP()
    if not hrp then return end
    platBV = Instance.new("BodyVelocity")
    platBV.Name = "ScorpHover"
    platBV.MaxForce = Vector3.new(0, 400000, 0)
    platBV.Velocity = Vector3.new(0, 0, 0)
    platBV.Parent = hrp
end
function Features.SetPlatform(on)
    platOn = on and true or false
    platApply()
end

function Features.SetHip(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    hipValue = n
    local hum = getHum()
    if hum then hum.HipHeight = hipValue end
end

function Features.SetAntivoid(on) voidOn = on and true or false end

local function invisApply()
    local c = getChar()
    if not c then return end
    local desc = c:GetDescendants()
    for i = 1, #desc do
        local p = desc[i]
        if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then
            p.LocalTransparencyModifier = invisOn and 1 or 0
        end
    end
end
function Features.SetInvisible(on)
    invisOn = on and true or false
    invisApply()
end

local fcOn = false
local fcPos = Vector3.new()
local fcYaw, fcPitch = 0, 0
local fcKeys = { W = false, A = false, S = false, D = false, E = false, Q = false, Shift = false }

function Features.SetFreecam(on)
    fcOn = on and true or false
    local cam = workspace.CurrentCamera
    if not cam then return end
    if fcOn then
        fcPos = cam.CFrame.Position
        local look = cam.CFrame.LookVector
        fcYaw = math.deg(math.atan2(-look.X, -look.Z))
        fcPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        cam.CameraType = Enum.CameraType.Scriptable
    else
        cam.CameraType = Enum.CameraType.Custom
        local hum = getHum()
        if hum then cam.CameraSubject = hum end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        for k in pairs(fcKeys) do fcKeys[k] = false end
    end
end
function Features.FreecamOn() return fcOn end

function Features.FirstPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
end
function Features.ThirdPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.Classic
    LocalPlayer.CameraMaxZoomDistance = 128
end
function Features.FixCam()
    local cam = workspace.CurrentCamera
    if not cam then return end
    cam.CameraType = Enum.CameraType.Custom
    local hum = getHum()
    if hum then cam.CameraSubject = hum end
    if fcOn then
        fcOn = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

-- ── hitbox ────────────────────────────────────────────────────────────────
local hitboxOn = false
local hitboxVisible = true
local hitboxSize = 5
local hbOriginals = {}
local HITBOX_COLOR = Color3.fromRGB(255, 40, 40)

local function hbRestore()
    for hrp, o in pairs(hbOriginals) do
        if hrp and hrp.Parent then
            hrp.Size = o.Size
            hrp.Transparency = o.Transparency
            hrp.Color = o.Color
            hrp.CanCollide = o.CanCollide
            hrp.Massless = o.Massless
        end
    end
    hbOriginals = {}
end

function Features.SetHitbox(on)
    hitboxOn = on and true or false
    if not hitboxOn then hbRestore() end
end
function Features.SetHitboxVisible(on) hitboxVisible = on and true or false end
function Features.SetHitboxSize(n)
    n = tonumber(n) or hitboxSize
    if n < 1 then n = 1 end
    if n > 10 then n = 10 end
    hitboxSize = n
end

-- ── ESP ───────────────────────────────────────────────────────────────────
local espOn = false
local espBox, espName, espHealth, espDistance, espSkeleton, espTracer, espChams = true, true, false, false, false, false, false
local espMax = 0
local espColor = Color3.fromRGB(230, 68, 68)
local espObjects = {}
local drawingOk = (Drawing ~= nil)

local SKELETON_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local SKELETON_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function espHide(o)
    o.box.Visible = false
    o.name.Visible = false
    o.hpBg.Visible = false
    o.hpFill.Visible = false
    o.tracer.Visible = false
    for i = 1, #o.bones do o.bones[i].Visible = false end
    if o.highlight then o.highlight.Enabled = false end
end

local function espRemove(plr)
    local o = espObjects[plr]
    if not o then return end
    pcall(function() o.box:Remove() end)
    pcall(function() o.name:Remove() end)
    pcall(function() o.hpBg:Remove() end)
    pcall(function() o.hpFill:Remove() end)
    pcall(function() o.tracer:Remove() end)
    for i = 1, #o.bones do pcall(function() o.bones[i]:Remove() end) end
    if o.highlight then o.highlight:Destroy() end
    espObjects[plr] = nil
end

local function espAdd(plr)
    if not drawingOk or plr == LocalPlayer or espObjects[plr] then return end
    local bones = {}
    for i = 1, 16 do
        bones[i] = newDrawing("Line", { Thickness = 1, Color = Color3.new(1, 1, 1), Visible = false })
    end
    espObjects[plr] = {
        box = newDrawing("Square", { Thickness = 1.5, Color = espColor, Filled = false, Visible = false }),
        name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.new(1, 1, 1), Visible = false }),
        hpBg = newDrawing("Square", { Thickness = 1, Color = Color3.new(0, 0, 0), Filled = true, Visible = false }),
        hpFill = newDrawing("Square", { Thickness = 1, Color = Color3.fromRGB(70, 210, 110), Filled = true, Visible = false }),
        tracer = newDrawing("Line", { Thickness = 1, Color = espColor, Visible = false }),
        bones = bones,
        highlight = nil,
    }
end

function Features.HasDrawing() return drawingOk end
function Features.SetEsp(on)
    espOn = on and drawingOk or false
    if not espOn then
        for _, o in pairs(espObjects) do espHide(o) end
    end
    return espOn
end
function Features.EspOn() return espOn end
function Features.SetEspFlag(name, on)
    on = on and true or false
    if name == "box" then espBox = on
    elseif name == "name" then espName = on
    elseif name == "health" then espHealth = on
    elseif name == "distance" then espDistance = on
    elseif name == "skeleton" then espSkeleton = on
    elseif name == "tracer" then espTracer = on
    elseif name == "chams" then espChams = on
    end
end
function Features.SetEspDistance(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    espMax = n
end
function Features.SetEspColor(c)
    if typeof(c) == "Color3" then espColor = c end
end

-- ── players ───────────────────────────────────────────────────────────────
local spectating = nil
local carryMode, carryTarget = nil, nil

function Features.TeleportTo(query)
    local target = findPlayer(query)
    local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local my = getHRP()
    if not (thrp and my) then return "player not found" end
    my.CFrame = thrp.CFrame + Vector3.new(0, 0, 3)
    return "teleported to " .. target.Name
end

function Features.Spectate(query)
    local cam = workspace.CurrentCamera
    if spectating then
        local hum = getHum()
        if hum and cam then cam.CameraSubject = hum end
        spectating = nil
        return "stopped spectating"
    end
    local target = findPlayer(query)
    local thum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if not (thum and cam) then return "player not found" end
    cam.CameraSubject = thum
    spectating = target
    return "spectating " .. target.Name
end

function Features.StopSpectate()
    local cam = workspace.CurrentCamera
    local hum = getHum()
    if hum and cam then cam.CameraSubject = hum end
    spectating = nil
end

function Features.SetCarry(mode, query)
    local target = findPlayer(query)
    if not target then
        carryMode, carryTarget = nil, nil
        return "player not found"
    end
    if carryMode == mode and carryTarget == target then
        carryMode, carryTarget = nil, nil
        return "stopped"
    end
    carryMode, carryTarget = mode, target
    return mode .. " -> " .. target.Name
end

function Features.Behind(query)
    local target = findPlayer(query)
    local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local my = getHRP()
    if not (thrp and my) then return "player not found" end
    my.CFrame = thrp.CFrame * CFrame.new(0, 0, 2.5)
    return "behind " .. target.Name
end

function Features.TeleportCoords(x, y, z)
    local hrp = getHRP()
    if not hrp then return "no character" end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return "enter X, Y and Z" end
    hrp.CFrame = CFrame.new(x, y, z)
    return "teleported"
end

function Features.GetPos()
    local hrp = getHRP()
    if not hrp then return nil end
    local p = hrp.Position
    return string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)
end

local clickMouse = nil
function Features.ClickTP()
    local root, hum = getHRP(), getHum()
    if not (root and hum) or hum.Health <= 0 then return "no character" end
    if not clickMouse then clickMouse = LocalPlayer:GetMouse() end
    if not clickMouse or not clickMouse.Target or not clickMouse.Hit then
        return "nothing under the cursor"
    end
    root.CFrame = CFrame.new(clickMouse.Hit.Position + Vector3.new(0, 3, 0))
    return nil
end

-- ── staff panel (firebase admins; receivers are other clients running this) ─
local ADMIN_IDS, ADMIN_NAMES = {}, {}
local isAdmin = false
local FIREBASE_URL, API_KEY, API_MODE = "", "", false
local seenCmd = {}
local startedAt = os.time() - 5
local staffStatus = "staff: not loaded"
local requestFn = nil

local SELF_SAFE = {
    fw = true, spn = true, frz = true, flg = true, sit = true,
    jmp = true, brg = true, vod = true, rst = true, bld = true, kck = true,
    usp = true, thw = true, ubl = true,
}
local PROTECTED = { vod = true, rst = true, kck = true }

local spinConn = nil
local blindGui = nil

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(body) == "string" and body ~= "" then return body end
    local req = requestFn or request or (syn and syn.request) or http_request
    if req then
        local ok2, resp = pcall(req, { Url = url, Method = "GET" })
        if ok2 and resp and type(resp.Body) == "string" and resp.Body ~= "" then
            return resp.Body
        end
    end
    return nil
end

local function httpReq(method, url, body)
    local req = requestFn or request or (syn and syn.request) or http_request
    if not req then return false end
    local ok, resp = pcall(req, {
        Url = url, Method = method, Body = body,
        Headers = { ["Content-Type"] = "application/json" },
    })
    if not ok or not resp then return false end
    local code = tonumber(resp.StatusCode or resp.Status or resp.status or resp.code)
    return code == nil or (code >= 200 and code < 300)
end

local function fbUrl(path)
    if FIREBASE_URL == "" then return "" end
    local q = ""
    if API_MODE and API_KEY ~= "" then
        q = "?key=" .. HttpService:UrlEncode(API_KEY)
    end
    return FIREBASE_URL .. "/" .. path .. q
end

local function addIdentity(raw)
    local s = tostring(raw or "")
    if s == "" then return end
    local id = tonumber(s)
    if id then ADMIN_IDS[id] = true else ADMIN_NAMES[string.lower(s)] = true end
end

local function clearMap(t)
    for k in pairs(t) do t[k] = nil end
end

local function applyStaff(body)
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" then return false end
    local has = type(data.ids) == "table" or type(data.usernames) == "table" or type(data.admins) == "table"
    if not has then return false end
    clearMap(ADMIN_IDS)
    clearMap(ADMIN_NAMES)
    local lists = { data.ids, data.usernames }
    for i = 1, #lists do
        local list = lists[i]
        if type(list) == "table" then
            for key, value in pairs(list) do
                if type(value) == "string" or type(value) == "number" then
                    addIdentity(value)
                elseif value == true then
                    addIdentity(key)
                end
            end
        end
    end
    if type(data.admins) == "table" then
        for i = 1, #data.admins do addIdentity(data.admins[i]) end
    end
    return true
end

local function loadFirebaseConfig()
    local buster = "?t=" .. tostring(os.time())
    local apiSources = {
        "https://raw.githubusercontent.com/vertxxy-1/Xyro/main/api.json" .. buster,
        "https://cdn.jsdelivr.net/gh/vertxxy-1/Xyro@main/api.json",
    }
    for i = 1, #apiSources do
        local body = httpGet(apiSources[i])
        if type(body) == "string" and body ~= "" then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and type(data) == "table" then
                local api = data.api or data
                if type(api) == "table" and type(api.url) == "string" and api.url ~= "" then
                    FIREBASE_URL = string.gsub(api.url, "/+$", "")
                    API_KEY = tostring(api.key or "")
                    API_MODE = true
                    return
                end
            end
            return
        end
    end
    local fbSources = {
        "https://raw.githubusercontent.com/vertxxy-1/Xyro/main/firebase.json" .. buster,
        "https://cdn.jsdelivr.net/gh/vertxxy-1/Xyro@main/firebase.json",
    }
    for i = 1, #fbSources do
        local body = httpGet(fbSources[i])
        if type(body) == "string" and body ~= "" then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and type(data) == "table" then
                local fb = data.firebase or data
                if type(fb) == "table" and type(fb.url) == "string" and fb.url ~= "" then
                    FIREBASE_URL = string.gsub(fb.url, "/+$", "")
                end
            elseif string.sub(body, 1, 8) == "https://" then
                FIREBASE_URL = string.gsub(body, "%s+", "")
            end
            return
        end
    end
end

local function refreshAdminFlag()
    isAdmin = ADMIN_IDS[LocalPlayer.UserId] == true or ADMIN_NAMES[string.lower(LocalPlayer.Name)] == true
    if FIREBASE_URL == "" then
        staffStatus = "staff: firebase not configured"
    elseif isAdmin then
        staffStatus = "staff: you are an administrator"
    else
        staffStatus = "staff: loaded (you are not staff)"
    end
end

function Features.RefreshStaff()
    local url = fbUrl("staff.json")
    if url == "" then
        staffStatus = "staff: firebase not configured"
        return staffStatus
    end
    local body = httpGet(url)
    if type(body) ~= "string" or body == "" or body == "null" then
        staffStatus = "staff: fetch failed"
        return staffStatus
    end
    if applyStaff(body) then
        refreshAdminFlag()
        return staffStatus
    end
    staffStatus = "staff: bad staff list"
    return staffStatus
end

function Features.StaffStatus() return staffStatus end
function Features.IsStaff() return isAdmin end

local function fxSettle(delay)
    task.delay(delay, function()
        local hum, hrp = getHum(), getHRP()
        if not hum then return end
        if hrp then hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end
        hum.PlatformStand = false
        if hum:GetState() == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function fxSpin(on)
    if spinConn then spinConn:Disconnect() spinConn = nil end
    if on then
        spinConn = connect(RunService.Heartbeat, function(dt)
            local hrp = getHRP()
            if hrp then hrp.CFrame = hrp.CFrame * CFrame.Angles(0, dt * 16, 0) end
        end)
    end
end

local function fxFlywheel()
    local hrp, hum = getHRP(), getHum()
    if not (hrp and hum) then return end
    local old = hrp:FindFirstChild("ScorpFlyWheel")
    if old then old:Destroy() end
    local lift = Instance.new("BodyVelocity")
    lift.Name = "ScorpFlyWheel"
    lift.MaxForce = Vector3.new(0, math.huge, 0)
    lift.Velocity = Vector3.new(0, 130, 0)
    lift.Parent = hrp
    task.wait(1.15)
    if lift.Parent then lift:Destroy() end
    local c = getChar()
    if c then
        local desc = c:GetDescendants()
        for i = 1, #desc do
            local p = desc[i]
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity = Vector3.new(math.random(-80, 80), math.random(40, 110), math.random(-80, 80))
            end
        end
    end
    hum:ChangeState(Enum.HumanoidStateType.Physics)
    fxSettle(2)
end

local function fxFreeze(on)
    local hrp, hum = getHRP(), getHum()
    if hrp then hrp.Anchored = on end
    if hum then
        hum.PlatformStand = on
        if not on then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
end

local function fxFling()
    local hrp, hum = getHRP(), getHum()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Physics) end
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.new(math.random(-160, 160), math.random(90, 180), math.random(-160, 160))
        hrp.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-12, 12), math.random(-8, 8))
    end
    fxSettle(1.6)
end

local function fxBlind(on)
    if blindGui then blindGui:Destroy() blindGui = nil end
    if not on then return end
    local host = (gethui and gethui()) or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not host then return end
    local g = Instance.new("ScreenGui")
    g.Name = "ScorpStaffBlind"
    g.IgnoreGuiInset = true
    g.ResetOnSpawn = false
    g.DisplayOrder = 100000
    local cover = Instance.new("Frame")
    cover.BackgroundColor3 = Color3.new(0, 0, 0)
    cover.BorderSizePixel = 0
    cover.Size = UDim2.fromScale(1, 1)
    cover.Parent = g
    g.Parent = host
    blindGui = g
end

local function staffIsAdmin(userId, userName)
    if ADMIN_IDS[userId] == true then return true end
    if type(userName) == "string" and ADMIN_NAMES[string.lower(userName)] == true then return true end
    return false
end

local function applyCmd(cmd, issuerId, issuerName)
    if not staffIsAdmin(issuerId, issuerName) then return end
    cmd = string.lower(tostring(cmd or ""))
    if issuerId == LocalPlayer.UserId and SELF_SAFE[cmd] then return end
    if PROTECTED[cmd] and isAdmin then return end
    if cmd == "fw" then task.spawn(fxFlywheel)
    elseif cmd == "spn" then task.spawn(fxSpin, true)
    elseif cmd == "usp" then task.spawn(fxSpin, false)
    elseif cmd == "frz" then task.spawn(fxFreeze, true)
    elseif cmd == "thw" then task.spawn(fxFreeze, false)
    elseif cmd == "flg" then task.spawn(fxFling)
    elseif cmd == "sit" then
        local hum = getHum()
        if hum then hum.Sit = true end
    elseif cmd == "jmp" then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    elseif cmd == "brg" then
        task.spawn(function()
            if not issuerId or issuerId == LocalPlayer.UserId then return end
            local issuer = Players:GetPlayerByUserId(issuerId)
            local target = issuer and issuer.Character and issuer.Character:FindFirstChild("HumanoidRootPart")
            local hrp = getHRP()
            if target and hrp then hrp.CFrame = target.CFrame * CFrame.new(0, 0, 3) end
        end)
    elseif cmd == "vod" then
        local hrp = getHRP()
        if hrp then hrp.CFrame = CFrame.new(hrp.Position.X, -400, hrp.Position.Z) end
    elseif cmd == "rst" then
        local hum = getHum()
        if hum then hum.Health = 0 end
    elseif cmd == "bld" then fxBlind(true)
    elseif cmd == "ubl" then fxBlind(false)
    elseif cmd == "kck" then
        pcall(function() LocalPlayer:Kick("Kicked by staff") end)
    end
end

local function targetsMe(payload)
    for idText in string.gmatch(payload or "", "%d+") do
        if tonumber(idText) == LocalPlayer.UserId then return true end
    end
    return false
end

local function handleWire(msg)
    if type(msg) ~= "string" or #msg == 0 or #msg >= 180 then return end
    local issuerId, issuerName, rest = string.match(msg, "^(%d+)|([^|]+)|(.+)$")
    if not (issuerId and rest) then return end
    local cmd, targets = string.match(rest, "^([%a]+):?(.*)$")
    if not cmd or cmd == "" then return end
    if targets == nil or targets == "" or targetsMe(targets) then
        applyCmd(cmd, tonumber(issuerId), issuerName)
    end
end

local function pollFirebase()
    local url = fbUrl("cmd.json")
    if url == "" then return end
    local body = httpGet(url)
    if type(body) ~= "string" or body == "" or body == "null" then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" or data.error ~= nil then return end
    local now = os.time()
    for key, value in pairs(data) do
        local sec = tonumber(string.match(tostring(key), "^(%d+)%-"))
        if type(value) == "string" and sec and (now - sec) <= 90 and sec >= startedAt and sec <= now + 120 and not seenCmd[key] then
            seenCmd[key] = true
            handleWire(value)
        end
    end
end

local function staffSend(cmd, targets)
    if not isAdmin then return false, "staff only" end
    local body = tostring(LocalPlayer.UserId) .. "|" .. LocalPlayer.Name .. "|" .. tostring(cmd) .. ":" .. tostring(targets or "")
    local url = fbUrl("cmd/" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 99999999)) .. ".json")
    if url == "" then return false, "firebase not configured" end
    local payload = HttpService:JSONEncode(body)
    if httpReq("PUT", url, payload) then return true, "sent" end
    return false, "send failed"
end

function Features.StaffAction(cmd, query)
    if not isAdmin then return false, staffStatus end
    local targets = ""
    if query and query ~= "" then
        local p = findPlayer(query)
        if not p then return false, "no player matched" end
        targets = tostring(p.UserId)
    end
    return staffSend(cmd, targets)
end

function Features.Start(opts)
    if started or not alive then return staffStatus end
    started = true
    opts = opts or {}
    requestFn = opts.request
    pcall(loadFirebaseConfig)
    pcall(function() Features.RefreshStaff() end)
    if not alive then return staffStatus end

    local existing = Players:GetPlayers()
    for i = 1, #existing do espAdd(existing[i]) end
    connect(Players.PlayerAdded, espAdd)
    connect(Players.PlayerRemoving, function(plr)
        espRemove(plr)
        if spectating == plr then Features.StopSpectate() end
        if carryTarget == plr then carryMode, carryTarget = nil, nil end
    end)

    connect(workspace:GetPropertyChangedSignal("Gravity"), function()
        if not applyingGravity and not gravOn then
            normalGravity = workspace.Gravity
            if normalGravity == 0 then normalGravity = 196.2 end
        end
    end)

    connect(UserInputService.JumpRequest, function()
        if not infJumpOn then return end
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)

    connect(UserInputService.InputBegan, function(input, gp)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = input.KeyCode.Name
        if flyOn and not gp then
            if name == "W" then flyMove.f = 1
            elseif name == "S" then flyMove.b = 1
            elseif name == "A" then flyMove.l = 1
            elseif name == "D" then flyMove.r = 1
            end
        end
        if fcOn and not gp then
            if fcKeys[name] ~= nil then fcKeys[name] = true end
            if input.KeyCode == Enum.KeyCode.LeftShift then fcKeys.Shift = true end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = input.KeyCode.Name
        if name == "W" then flyMove.f = 0
        elseif name == "S" then flyMove.b = 0
        elseif name == "A" then flyMove.l = 0
        elseif name == "D" then flyMove.r = 0
        end
        if fcKeys[name] ~= nil then fcKeys[name] = false end
        if input.KeyCode == Enum.KeyCode.LeftShift then fcKeys.Shift = false end
    end)

    connect(LocalPlayer.CharacterAdded, function(c)
        if flyOn then
            flyOn = false
            stopFly()
        end
        noclipParts = {}
        c:WaitForChild("Humanoid")
        applyWalk()
        applyJump()
        if hipValue then
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum then hum.HipHeight = hipValue end
        end
        if platOn then platApply() end
        if invisOn then task.delay(0.2, invisApply) end
    end)

    connect(RunService.Stepped, function()
        if not alive then return end
        if cframeOn then
            local hrp, hum = getHRP(), getHum()
            if hrp and hum then
                hrp.CFrame = hrp.CFrame + hum.MoveDirection * cframeSpeed * 0.1
            end
        end
        if noclipOn then
            local c = getChar()
            if c then
                local desc = c:GetDescendants()
                for i = 1, #desc do
                    local part = desc[i]
                    if part:IsA("BasePart") and part.CanCollide then
                        if noclipParts[part] == nil then noclipParts[part] = true end
                        part.CanCollide = false
                    end
                end
            end
        end
    end)

    connect(RunService.Heartbeat, function()
        if not alive then return end
        if hitboxOn then
            local sizeVec = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
            local tp = hitboxVisible and 0.75 or 1
            local list = Players:GetPlayers()
            for i = 1, #list do
                local plr = list[i]
                if plr ~= LocalPlayer and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        if not hbOriginals[hrp] then
                            hbOriginals[hrp] = {
                                Size = hrp.Size, Transparency = hrp.Transparency,
                                Color = hrp.Color, CanCollide = hrp.CanCollide, Massless = hrp.Massless,
                            }
                        end
                        hrp.Size = sizeVec
                        hrp.CanCollide = false
                        hrp.Transparency = tp
                        hrp.Color = HITBOX_COLOR
                        hrp.Massless = true
                    end
                end
            end
        end
        if airOn then
            local hrp = getHRP()
            if hrp then
                if not (airPart and airPart.Parent) then
                    airPart = Instance.new("Part")
                    airPart.Name = "ScorpAirwalk"
                    airPart.Anchored = true
                    airPart.CanCollide = true
                    airPart.Size = Vector3.new(7, 1, 7)
                    airPart.Transparency = 1
                    airPart.Parent = workspace
                end
                airPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - airOffset - 0.5, hrp.Position.Z)
            end
        end
        if voidOn then
            local hrp, hum = getHRP(), getHum()
            if hrp and hum then
                if hum.FloorMaterial ~= Enum.Material.Air then lastSafe = hrp.CFrame end
                if hrp.Position.Y < workspace.FallenPartsDestroyHeight + 50 and lastSafe then
                    hrp.CFrame = lastSafe + Vector3.new(0, 5, 0)
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
            end
        end
        if antiflingOn then
            local hum, hrp = getHum(), getHRP()
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            end
            if hrp and (hrp.AssemblyLinearVelocity.Magnitude > 100 or hrp.AssemblyAngularVelocity.Magnitude > 50) then
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
        end
    end)

    connect(RunService.RenderStepped, function(dt)
        if not alive then return end
        if spinOn then
            local root = getHRP()
            if root then root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0) end
        end
        if flyOn and flyBV and flyBG then
            local cam = workspace.CurrentCamera
            if cam then
                local fwd = flyMove.f - flyMove.b
                local side = flyMove.r - flyMove.l
                local inputVec = (cam.CFrame.LookVector * fwd) + (cam.CFrame.RightVector * side)
                local desired = Vector3.new(0, 0, 0)
                if inputVec.Magnitude > 0 then desired = inputVec.Unit * flySpeed end
                flyBV.Velocity = desired
                flyBG.CFrame = cam.CFrame
            end
        end
        if carryMode and carryTarget then
            local thrp = carryTarget.Character and carryTarget.Character:FindFirstChild("HumanoidRootPart")
            local my = getHRP()
            if not thrp or not my or carryTarget.Parent ~= Players then
                carryMode, carryTarget = nil, nil
            else
                local off = CFrame.new(0, 0, 4)
                if carryMode == "head" then off = CFrame.new(0, 3.2, 0)
                elseif carryMode == "back" then off = CFrame.new(0, 0.4, 1.6)
                end
                my.CFrame = (thrp.CFrame * off) + thrp.AssemblyLinearVelocity * 0.03
                my.AssemblyLinearVelocity = thrp.AssemblyLinearVelocity
            end
        end
        if lockFovOn and workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = fov
        end
        if invisOn then invisApply() end
        if fcOn and workspace.CurrentCamera then
            local cam = workspace.CurrentCamera
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            local d = UserInputService:GetMouseDelta()
            fcYaw = fcYaw - d.X * 0.3
            fcPitch = math.clamp(fcPitch - d.Y * 0.3, -89, 89)
            local rot = CFrame.fromEulerAnglesYXZ(math.rad(fcPitch), math.rad(fcYaw), 0)
            local speed = (fcKeys.Shift and 4 or 1) * 60 * dt
            local move = Vector3.new(0, 0, 0)
            if fcKeys.W then move = move + rot.LookVector end
            if fcKeys.S then move = move - rot.LookVector end
            if fcKeys.D then move = move + rot.RightVector end
            if fcKeys.A then move = move - rot.RightVector end
            if fcKeys.E then move = move + Vector3.new(0, 1, 0) end
            if fcKeys.Q then move = move - Vector3.new(0, 1, 0) end
            if move.Magnitude > 0 then fcPos = fcPos + move.Unit * speed end
            cam.CFrame = CFrame.new(fcPos) * rot
        end

        if espOn and drawingOk then
            local cam = workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                for plr, o in pairs(espObjects) do
                    local ch = plr.Character
                    local head = ch and ch:FindFirstChild("Head")
                    local root = ch and ch:FindFirstChild("HumanoidRootPart")
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    if root and head and hum and hum.Health > 0 then
                        local dist = (cam.CFrame.Position - root.Position).Magnitude
                        local inRange = espMax <= 0 or dist <= espMax
                        local top, onTop = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local bot = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                        if onTop and inRange then
                            local height = math.abs(bot.Y - top.Y)
                            local width = height * 0.5
                            local boxX = top.X - width / 2
                            if espBox then
                                o.box.Color = espColor
                                o.box.Size = Vector2.new(width, height)
                                o.box.Position = Vector2.new(boxX, top.Y)
                                o.box.Visible = true
                            else
                                o.box.Visible = false
                            end
                            if espName or espDistance or espHealth then
                                local label = plr.Name
                                if espDistance then label = string.format("%s [%dm]", label, math.floor(dist)) end
                                if espHealth then label = string.format("%s (%d)", label, math.floor(hum.Health)) end
                                o.name.Text = label
                                o.name.Color = Color3.new(1, 1, 1)
                                o.name.Position = Vector2.new(top.X, top.Y - 16)
                                o.name.Visible = true
                            else
                                o.name.Visible = false
                            end
                            if espHealth then
                                local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                                local barW, barX = 3, boxX - 6
                                o.hpBg.Size = Vector2.new(barW, height)
                                o.hpBg.Position = Vector2.new(barX, top.Y)
                                o.hpBg.Visible = true
                                local fillH = height * pct
                                o.hpFill.Size = Vector2.new(barW, fillH)
                                o.hpFill.Position = Vector2.new(barX, top.Y + (height - fillH))
                                o.hpFill.Color = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(210 * pct), 90)
                                o.hpFill.Visible = true
                            else
                                o.hpBg.Visible = false
                                o.hpFill.Visible = false
                            end
                            if espSkeleton then
                                local rig = hum.RigType == Enum.HumanoidRigType.R15 and SKELETON_R15 or SKELETON_R6
                                local used = 0
                                for pi = 1, #rig do
                                    local a = ch:FindFirstChild(rig[pi][1])
                                    local b = ch:FindFirstChild(rig[pi][2])
                                    if a and b then
                                        local pa, va = cam:WorldToViewportPoint(a.Position)
                                        local pb, vb = cam:WorldToViewportPoint(b.Position)
                                        if va and vb then
                                            used = used + 1
                                            local ln = o.bones[used]
                                            if ln then
                                                ln.Color = espColor
                                                ln.From = Vector2.new(pa.X, pa.Y)
                                                ln.To = Vector2.new(pb.X, pb.Y)
                                                ln.Visible = true
                                            end
                                        end
                                    end
                                end
                                for j = used + 1, #o.bones do o.bones[j].Visible = false end
                            else
                                for j = 1, #o.bones do o.bones[j].Visible = false end
                            end
                            if espTracer then
                                local feet, onScreen = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                                if onScreen then
                                    o.tracer.Color = espColor
                                    o.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                                    o.tracer.To = Vector2.new(feet.X, feet.Y)
                                    o.tracer.Visible = true
                                else
                                    o.tracer.Visible = false
                                end
                            else
                                o.tracer.Visible = false
                            end
                            if espChams then
                                if not (o.highlight and o.highlight.Parent == ch) then
                                    o.highlight = Instance.new("Highlight")
                                    o.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                    o.highlight.FillTransparency = 0.5
                                    o.highlight.OutlineTransparency = 0
                                    o.highlight.Parent = ch
                                end
                                o.highlight.FillColor = espColor
                                o.highlight.OutlineColor = Color3.new(1, 1, 1)
                                o.highlight.Enabled = true
                            elseif o.highlight then
                                o.highlight.Enabled = false
                            end
                        else
                            espHide(o)
                        end
                    else
                        espHide(o)
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while alive do
            pcall(pollFirebase)
            task.wait(2)
        end
    end)
end

function Features.Cleanup()
    alive = false
    cframeOn, noclipOn, flyOn, gravOn = false, false, false, false
    hitboxOn, espOn, airOn, platOn = false, false, false, false
    invisOn, fcOn, voidOn, antiflingOn = false, false, false, false
    carryMode, carryTarget = nil, nil
    stopFly()
    noclipRestore()
    hbRestore()
    airClear()
    if platBV then platBV:Destroy() platBV = nil end
    if spinConn then spinConn:Disconnect() spinConn = nil end
    fxBlind(false)
    Features.StopSpectate()
    Features.FixCam()
    if worldOrig then
        fullbrightOn, nofogOn = false, false
        pcall(applyLighting)
    end
    pcall(function() Features.SetXray(false) end)
    pcall(function()
        if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = origFov end
    end)
    if infFolder then infFolder:Destroy() infFolder = nil end
    for plr in pairs(espObjects) do espRemove(plr) end
    for i = 1, #conns do
        pcall(function() conns[i]:Disconnect() end)
    end
    conns = {}
end

return Features

end)()

local function stub(name)
    return function(value)
        print(("[Scorp] %s -> %s"):format(name, tostring(value)))
    end
end

local Window = Scorp:CreateWindow({
    Title        = "SCORP",
    Subtitle     = "Made By Yuniku",
    Theme        = "Rayfield",
    Flat         = true,
    Starfield    = false,
    ToggleKey    = Enum.KeyCode.K,
    UnloadKey    = Enum.KeyCode.Delete,
    WidgetText   = "SCORP",
    LogoIcon     = "✦",
    ConfigFolder = "Scorp",
})

Window:SetWatermark('<font color="rgb(80,105,255)">Scorp</font>  ·  Made By Yuniku')

-- ───────────────────────────────────────────────────────────────────────────
--  Home
-- ───────────────────────────────────────────────────────────────────────────
local Home = Window:CreateTab("Home", { Icon = "🏄" })

do
    local sec = Home:CreateSection("Welcome", true)
    sec:AddLabel("Scorp is running. Everything here is a placeholder.", { Wrap = true })
    sec:AddLabel("Made by Drew", { Color = Window.Theme.TextDim })
    sec:AddButton("Test Notification", function()
        Window:Notify("Scorp", "Notifications are working.", 3)
    end)
    sec:AddButton("Success Notification", function()
        Window:Notify("Done", "This one uses the success colour.", 3, Window.Theme.Success)
    end)
end

do
    local sec = Home:CreateSection("Cosmic Core", true)
    -- Toggles show a [ None ] key box by default; add  Bindable = false  to hide it (Feature 1 keeps it as the example)
    sec:AddToggle("Placeholder Feature 1", { Flag = "core_1", Callback = stub("Placeholder Feature 1") })   -- TODO
    sec:AddToggle("Placeholder Feature 2", { Bindable = false, Flag = "core_2", Callback = stub("Placeholder Feature 2") })   -- TODO
    sec:AddToggle("Placeholder Feature 3", { Bindable = false, Flag = "core_3", Callback = stub("Placeholder Feature 3") })   -- TODO
    sec:AddSlider("Power Level", {
        Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
        Flag = "core_power", Callback = stub("Power Level"),                                                -- TODO
    })
    sec:AddDropdown("Mode:", {
        Options = { "Mode A", "Mode B", "Mode C" }, Default = "Mode A",
        Flag = "core_mode", Callback = stub("Mode"),                                                        -- TODO
    })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Player
-- ───────────────────────────────────────────────────────────────────────────
local Player = Window:CreateTab("Player", { Icon = "🌠" })

do
    local sec = Player:CreateSection("Movement", true)
    sec:AddToggle("Movement Toggle 1", { Bindable = false, Flag = "move_1", Callback = stub("Movement Toggle 1") })           -- TODO
    sec:AddToggle("Movement Toggle 2", { Bindable = false, Flag = "move_2", Callback = stub("Movement Toggle 2") })           -- TODO
    sec:AddSlider("Value Slider 1", { Min = 0, Max = 100, Default = 16, Flag = "move_v1", Callback = stub("Value Slider 1") })  -- TODO
    sec:AddSlider("Value Slider 2", { Min = 0, Max = 200, Default = 50, Flag = "move_v2", Callback = stub("Value Slider 2") })  -- TODO
end

do
    local sec = Player:CreateSection("Character", false)
    sec:AddToggle("Character Toggle", { Bindable = false, Flag = "char_1", Callback = stub("Character Toggle") })             -- TODO
    sec:AddButton("Character Button", stub("Character Button"))                                             -- TODO
    sec:AddKeybind("Character Keybind", { Default = Enum.KeyCode.F, Flag = "char_key", Callback = stub("Character Keybind") })  -- TODO
end

-- ───────────────────────────────────────────────────────────────────────────
--  Visuals
-- ───────────────────────────────────────────────────────────────────────────
local Visuals = Window:CreateTab("Visuals", { Icon = "☄️" })

do
    local sec = Visuals:CreateSection("Glow", true)
    sec:AddToggle("Enable Glow", { Bindable = false, Flag = "vis_glow", Callback = stub("Enable Glow") })                     -- TODO
    sec:AddColorPicker("Glow Color", {
        Default = Color3.fromRGB(90, 210, 255), Flag = "vis_glow_color", Callback = stub("Glow Color"),     -- TODO
    })
    sec:AddSlider("Glow Strength", { Min = 0, Max = 100, Default = 40, Suffix = "%", Flag = "vis_glow_str", Callback = stub("Glow Strength") })  -- TODO
end

do
    local sec = Visuals:CreateSection("Overlay", false)
    sec:AddToggle("Overlay Toggle 1", { Bindable = false, Flag = "vis_o1", Callback = stub("Overlay Toggle 1") })             -- TODO
    sec:AddToggle("Overlay Toggle 2", { Bindable = false, Flag = "vis_o2", Callback = stub("Overlay Toggle 2") })             -- TODO
    sec:AddDropdown("Style:", { Options = { "Style 1", "Style 2", "Style 3" }, Default = "Style 1", Flag = "vis_style", Callback = stub("Style") })  -- TODO
end

-- ───────────────────────────────────────────────────────────────────────────
--  Misc — every feature, its keybind, and the staff panel live on this tab.
-- ───────────────────────────────────────────────────────────────────────────
local Misc = Window:CreateTab("Misc", { Icon = "🌌" })

local function note(title, text, bad)
    Window:Notify(title, tostring(text or ""), 3, bad and Window.Theme.Danger or nil)
end

do
    local sec = Misc:CreateSection("Movement", true)
    sec:AddLabel("Click the key chip on a row to rebind it. Defaults: C speed, X fly, G gravity, F click TP, K menu.")
    sec:AddToggle("CFrame movement", {
        Keybind = Enum.KeyCode.C, Flag = "misc_cframe",
        Callback = function(on) Features.SetCFrame(on) end,
    })
    sec:AddSlider("CFrame speed", {
        Min = 0, Max = 500, Default = 16, Increment = 1, Flag = "misc_cframe_speed",
        Callback = function(v) Features.SetCFrameSpeed(v) end,
    })
    sec:AddToggle("Fly", {
        Keybind = Enum.KeyCode.X, Flag = "misc_fly",
        Callback = function(on) Features.SetFly(on) end,
    })
    sec:AddSlider("Fly speed", {
        Min = 0, Max = 500, Default = 50, Increment = 1, Flag = "misc_fly_speed",
        Callback = function(v) Features.SetFlySpeed(v) end,
    })
    sec:AddToggle("Noclip", {
        Bindable = true, Flag = "misc_noclip",
        Callback = function(on) Features.SetNoclip(on) end,
    })
    sec:AddToggle("Infinite jump", {
        Bindable = true, Flag = "misc_infjump",
        Callback = function(on) Features.SetInfJump(on) end,
    })
    sec:AddSlider("Walk speed", {
        Min = 0, Max = 500, Default = 16, Increment = 1, Flag = "misc_ws",
        Callback = function(v) Features.SetWalkSpeed(v) end,
    })
    sec:AddSlider("Jump power", {
        Min = 0, Max = 500, Default = 50, Increment = 1, Flag = "misc_jp",
        Callback = function(v) Features.SetJumpPower(v) end,
    })
    sec:AddToggle("Spin", {
        Bindable = true, Flag = "misc_spin",
        Callback = function(on) Features.SetSpin(on) end,
    })
    sec:AddSlider("Spin speed", {
        Min = -50, Max = 50, Default = 10, Increment = 1, Flag = "misc_spin_speed",
        Callback = function(v) Features.SetSpinSpeed(v) end,
    })
end

do
    local sec = Misc:CreateSection("World", false)
    sec:AddToggle("Custom gravity", {
        Keybind = Enum.KeyCode.G, Flag = "misc_grav",
        Callback = function(on) Features.SetGravity(on) end,
    })
    sec:AddSlider("Gravity", {
        Min = 0, Max = 500, Default = 196, Increment = 1, Flag = "misc_grav_v",
        Callback = function(v) Features.SetCustomGravity(v) end,
    })
    sec:AddToggle("Fullbright", {
        Bindable = true, Flag = "misc_fb",
        Callback = function(on) Features.SetFullbright(on) end,
    })
    sec:AddToggle("No fog", {
        Bindable = true, Flag = "misc_nofog",
        Callback = function(on) Features.SetNoFog(on) end,
    })
    sec:AddToggle("X-ray", {
        Bindable = true, Flag = "misc_xray",
        Callback = function(on) Features.SetXray(on) end,
    })
    sec:AddToggle("Anti-fling", {
        Bindable = true, Flag = "misc_antifling",
        Callback = function(on) Features.SetAntifling(on) end,
    })
    sec:AddSlider("FOV", {
        Min = 1, Max = 120, Default = 70, Increment = 1, Flag = "misc_fov",
        Callback = function(v) Features.SetFov(v) end,
    })
    sec:AddToggle("Lock FOV", {
        Bindable = true, Flag = "misc_lockfov",
        Callback = function(on) Features.SetLockFov(on) end,
    })
    sec:AddButton("Infbaseplate", function()
        note("World", Features.ToggleInfBaseplate())
    end)
end

do
    local sec = Misc:CreateSection("ESP", false)
    sec:AddToggle("ESP", {
        Bindable = true, Flag = "misc_esp",
        Callback = function(on)
            local ok = Features.SetEsp(on)
            if on and not ok then
                note("ESP", "This executor has no Drawing API", true)
            end
        end,
    })
    sec:AddToggle("Box", { Default = true, Bindable = false, Flag = "misc_esp_box", Callback = function(on) Features.SetEspFlag("box", on) end })
    sec:AddToggle("Name", { Default = true, Bindable = false, Flag = "misc_esp_name", Callback = function(on) Features.SetEspFlag("name", on) end })
    sec:AddToggle("Health", { Bindable = false, Flag = "misc_esp_hp", Callback = function(on) Features.SetEspFlag("health", on) end })
    sec:AddToggle("Distance", { Bindable = false, Flag = "misc_esp_dist", Callback = function(on) Features.SetEspFlag("distance", on) end })
    sec:AddToggle("Skeleton", { Bindable = false, Flag = "misc_esp_skel", Callback = function(on) Features.SetEspFlag("skeleton", on) end })
    sec:AddToggle("Tracers", { Bindable = false, Flag = "misc_esp_tr", Callback = function(on) Features.SetEspFlag("tracer", on) end })
    sec:AddToggle("Chams", { Bindable = false, Flag = "misc_esp_chams", Callback = function(on) Features.SetEspFlag("chams", on) end })
    sec:AddSlider("Max distance (0 = unlimited)", {
        Min = 0, Max = 1000, Default = 0, Increment = 10, Suffix = " studs", Flag = "misc_esp_max",
        Callback = function(v) Features.SetEspDistance(v) end,
    })
    sec:AddColorPicker("ESP color", {
        Default = Color3.fromRGB(230, 68, 68), Flag = "misc_esp_color",
        Callback = function(c) Features.SetEspColor(c) end,
    })
end

do
    local sec = Misc:CreateSection("Hitbox", false)
    sec:AddToggle("Hitbox extender", {
        Bindable = true, Flag = "misc_hb",
        Callback = function(on) Features.SetHitbox(on) end,
    })
    sec:AddToggle("Show box", {
        Default = true, Bindable = false, Flag = "misc_hb_show",
        Callback = function(on) Features.SetHitboxVisible(on) end,
    })
    sec:AddSlider("Hitbox size", {
        Min = 1, Max = 10, Default = 5, Increment = 1, Flag = "misc_hb_size",
        Callback = function(v) Features.SetHitboxSize(v) end,
    })
end

do
    local sec = Misc:CreateSection("Players", false)
    local playerBox = sec:AddTextbox("Player", {
        Placeholder = "name or display name", Flag = "misc_player", CallOnBlur = true,
    })
    local xBox = sec:AddTextbox("X", { Placeholder = "X", Flag = "misc_x" })
    local yBox = sec:AddTextbox("Y", { Placeholder = "Y", Flag = "misc_y" })
    local zBox = sec:AddTextbox("Z", { Placeholder = "Z", Flag = "misc_z" })
    local function q() return playerBox:Get() end
    sec:AddButton("Teleport", function() note("Players", Features.TeleportTo(q())) end)
    sec:AddButton("Spectate / stop", function() note("Players", Features.Spectate(q())) end)
    sec:AddButton("Head sit", function() note("Players", Features.SetCarry("head", q())) end)
    sec:AddButton("Backpack", function() note("Players", Features.SetCarry("back", q())) end)
    sec:AddButton("Focus TP", function() note("Players", Features.SetCarry("focus", q())) end)
    sec:AddButton("Behind", function() note("Players", Features.Behind(q())) end)
    sec:AddButton("TP to coords", function()
        note("Players", Features.TeleportCoords(xBox:Get(), yBox:Get(), zBox:Get()))
    end)
    sec:AddButton("Get position", function()
        local s = Features.GetPos()
        if not s then note("Players", "no character", true) return end
        local x, y, z = string.match(s, "^(-?[%d%.]+),%s*(-?[%d%.]+),%s*(-?[%d%.]+)$")
        if x then
            xBox:Set(x, true)
            yBox:Set(y, true)
            zBox:Set(z, true)
        end
        local fn = setclipboard or toclipboard
        if type(fn) == "function" then pcall(fn, s) end
        note("Players", s)
    end)
    sec:AddKeybind("Click TP", {
        Default = Enum.KeyCode.F, Flag = "misc_clicktp",
        Callback = function()
            local msg = Features.ClickTP()
            if msg then note("Click TP", msg, true) end
        end,
    })
end

do
    local sec = Misc:CreateSection("Camera", false)
    sec:AddToggle("Freecam", {
        Bindable = true, Flag = "misc_fc",
        Callback = function(on) Features.SetFreecam(on) end,
    })
    sec:AddButton("First person", function() Features.FirstPerson() note("Camera", "first person") end)
    sec:AddButton("Third person", function() Features.ThirdPerson() note("Camera", "third person") end)
    sec:AddButton("Reset camera", function() Features.FixCam() note("Camera", "camera reset") end)
end

do
    local sec = Misc:CreateSection("Extra", false)
    sec:AddToggle("Airwalk", {
        Bindable = true, Flag = "misc_air",
        Callback = function(on) Features.SetAirwalk(on) end,
    })
    sec:AddSlider("Airwalk offset", {
        Min = -20, Max = 20, Default = 3, Increment = 1, Flag = "misc_air_off",
        Callback = function(v) Features.SetAirOffset(v) end,
    })
    sec:AddToggle("Platform hover", {
        Bindable = true, Flag = "misc_plat",
        Callback = function(on) Features.SetPlatform(on) end,
    })
    sec:AddSlider("Hip height", {
        Min = 0, Max = 100, Default = 0, Increment = 1, Flag = "misc_hip",
        Callback = function(v) Features.SetHip(v) end,
    })
    sec:AddToggle("Anti-void", {
        Bindable = true, Flag = "misc_void",
        Callback = function(on) Features.SetAntivoid(on) end,
    })
    sec:AddToggle("Invisible (client)", {
        Bindable = true, Flag = "misc_invis",
        Callback = function(on) Features.SetInvisible(on) end,
    })
end

do
    local sec = Misc:CreateSection("Staff panel", false)
    local status = sec:AddLabel("Staff: loading…", { Wrap = true, Color = Window.Theme.TextDim })
    task.spawn(function()
        Features.Start({ request = http_request })
        status:Set(Features.StaffStatus())
    end)
    local targetBox = sec:AddTextbox("Target", {
        Placeholder = "username (blank = everyone)", Flag = "misc_staff_target", CallOnBlur = true,
    })
    local function act(cmd, label)
        local ok, msg = Features.StaffAction(cmd, targetBox:Get())
        note("Staff", ok and (label .. " sent") or msg, not ok)
    end
    sec:AddButton("Refresh staff list", function()
        local msg = Features.RefreshStaff()
        status:Set(msg)
        note("Staff", msg, not Features.IsStaff())
    end)
    sec:AddButton("Flywheel", function() act("fw", "flywheel") end)
    sec:AddButton("Freeze", function() act("frz", "freeze") end)
    sec:AddButton("Unfreeze", function() act("thw", "unfreeze") end)
    sec:AddButton("Fling", function() act("flg", "fling") end)
    sec:AddButton("Sit", function() act("sit", "sit") end)
    sec:AddButton("Jump", function() act("jmp", "jump") end)
    sec:AddButton("Bring to me", function()
        if targetBox:Get() == "" then
            note("Staff", "bring needs a specific player", true)
            return
        end
        act("brg", "bring")
    end)
    sec:AddButton("Void", function() act("vod", "void") end)
    sec:AddButton("Reset", function() act("rst", "reset") end)
    sec:AddButton("Blind", function() act("bld", "blind") end)
    sec:AddButton("Unblind", function() act("ubl", "unblind") end)
    sec:AddButton("Kick", function() act("kck", "kick") end)
    sec:AddButton("Spin on", function() act("spn", "spin") end)
    sec:AddButton("Spin off", function() act("usp", "unspin") end)
end


-- ───────────────────────────────────────────────────────────────────────────
--  Settings  (theme picker + config save/load come from the library)
-- ───────────────────────────────────────────────────────────────────────────
local Settings = Window:CreateTab("Settings", { Icon = "⚙️" })

Window:AddThemeControls(Settings, "🎨 Theme")
Window:AddConfigControls(Settings, "💾 Configs")

do
    local sec = Settings:CreateSection("Menu", true)
    sec:AddKeybind("Menu Toggle Key", {
        Default  = Window.ToggleKey,
        OnChange = function(key) Window:SetToggleKey(key) end,
    })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Cleanup
-- ───────────────────────────────────────────────────────────────────────────
Window:OnUnload(function()
    print("[Scorp] unloaded")
    pcall(Features.Cleanup)
end)

Window:Notify("Scorp", "Loaded. Press " .. Window.ToggleKey.Name .. " to toggle.", 4)

    return Window
end

-- ───────────────────────────────────────────────────────────────────────────
--  Ask the server if this user is allowed, then run the payload + hub
--  (Assumes the server answers 200 for whitelisted users and anything else
--   – e.g. 403 – for blacklisted / non-whitelisted users. Adjust if yours differs.)
-- ───────────────────────────────────────────────────────────────────────────
if not http_request then
    warn("[Scorp] your executor doesn't support HTTP requests.")
    return
end

-- Run the checks synchronously so the result is known before we ask for anything
local hits, score = runChecks()
if score >= REPORT_SCORE then reportHits(hits, score) end
headers["X-Session"] = SESSION_ID
headers["X-Flags"]   = table.concat(hits, ",")

if score >= BLOCK_SCORE then
    -- Same message as a normal denial so nobody learns what tripped
    warn("[Scorp] access denied (not whitelisted, blacklisted, or server unreachable).")
    return
end

local success, response = pcall(function()
    return http_request({
        Url = API_URL .. "/api/script",
        Method = "GET",
        Headers = headers
    })
end)

local allowed = success and response and response.Body
    and (response.StatusCode == 200 or response.Success == true)

if not allowed then
    warn("[Scorp] access denied (not whitelisted, blacklisted, or server unreachable).")
    return
end

-- Execute the protected payload
local func = loadstring(response.Body)
if func then
    local ok, err = pcall(func)
    if not ok then warn("[Scorp] payload error: " .. tostring(err)) end
end

local Window = startHub()

-- Heartbeat: re-run the checks and let the server revoke access mid-session
-- (blacklisted while running -> UI is torn down at the next beat).
task.spawn(function()
    while Window and not Window.Destroyed do
        task.wait(HEARTBEAT_EVERY)
        if Window.Destroyed then break end

        local hb, hbScore = runChecks()
        if hbScore >= REPORT_SCORE then reportHits(hb, hbScore) end

        local hbHeaders = {
            ["Content-Type"] = "application/json",
            ["X-User-ID"]    = headers["X-User-ID"],
            ["X-HWID"]       = headers["X-HWID"],
            ["X-Session"]    = SESSION_ID,
        }
        local ok, res = pcall(function()
            return http_request({
                Url     = API_URL .. "/api/heartbeat",
                Method  = "POST",
                Headers = hbHeaders,
                Body    = HttpService:JSONEncode({ flags = hb, score = hbScore }),
            })
        end)

        local revoked = (ok and res and (res.StatusCode == 401 or res.StatusCode == 403))
            or hbScore >= BLOCK_SCORE
        if revoked then
            pcall(function() Window:Destroy(true) end)
            break
        end
    end
end)
