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
}
Library.ThemeOrder = { "Nova Silver", "Silver Surfer", "Power Cosmic", "Zenn-La", "Deep Space" }

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
        Color = Color3.new(1, 1, 1), Thickness = thickness or 1, Transparency = transparency or 0.2,
    })
    self:_breathe(Make("UIGradient", { Parent = s, Rotation = 0 }))
    return s
end

--- The brand glyph: a bright head with a tapered comet-tail streak, drawn with plain
-- Frames (no image asset needed). Reused in the sidebar logo, the watermark, and
-- notification accents so the whole UI shares one recognizable mark.
function Window:_cometMark(parent, size, anchor, position)
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
        Tween(scale, { Scale = o.Grow or 1.04 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
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
    Corner(self.Main, 14)
    Make("UIGradient", { Parent = self.Main, Rotation = -45, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(205, 215, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 238, 255)),
    }) })
    self.mainStroke = Make("UIStroke", { Parent = self.Main, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2, Transparency = 0.15 })
    self:_bind(function(t) self.Main.BackgroundColor3 = t.MainBg; self.mainStroke.Color = t.Accent end)

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
    Make("UIGradient", { Parent = self.Sidebar, Rotation = 90, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 185, 225)) }) })
    local edge = Make("Frame", { Parent = self.Sidebar, Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    Make("UIGradient", { Parent = edge, Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }) })
    self:_bind(function(t) edge.BackgroundColor3 = t.Accent end)

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
    self:_breathe(Make("UIGradient", { Parent = logo, Rotation = 0 }))
    local logoGlow = Make("UIStroke", { Parent = logo, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 1.5, Transparency = 0.72 })
    self:_bind(function(t) logoGlow.Color = t.AccentLight end)
    if opts.Subtitle then
        Make("TextLabel", {
            Parent = logoArea, Size = UDim2.new(1, -20, 0, subtitleBlockHeight), Position = UDim2.new(0, 10, 0, markRow + 40),
            BackgroundTransparency = 1, Text = opts.Subtitle, TextColor3 = self.Theme.TextDim,
            Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
        })
    end
    local logoLine = Make("Frame", { Parent = logoArea, Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 1, -2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    local divGrad = Make("UIGradient", { Parent = logoLine, Rotation = 0, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.7) }) })
    self:_breathe(divGrad)
    local diamondGlow = Make("Frame", { Parent = logoArea, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(16, 16), Rotation = 45, BackgroundTransparency = 0.82, BorderSizePixel = 0 })
    Corner(diamondGlow, 3)
    Make("Frame", { Parent = logoArea, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(7, 7), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    self:_bind(function(t) diamondGlow.BackgroundColor3 = t.AccentLight end)

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
    local footLine = Make("Frame", { Parent = self._footer, Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
    self:_breathe(Make("UIGradient", { Parent = footLine, Rotation = 0, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.8) }) }))
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
        BackgroundColor3 = Color3.fromRGB(14, 18, 36), BackgroundTransparency = 0.2,
    })
    local notifScale = Make("UIScale", { Parent = notif, Scale = 0.85 })
    Corner(notif, 10)
    local stroke = Make("UIStroke", { Parent = notif, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = c, Thickness = 2, Transparency = 0.2 })
    if not color then self:_breathe(Make("UIGradient", { Parent = stroke, Rotation = 0 })) end

    if color then
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
            Tween(t._fg, { TextColor3 = self.Theme.TextWhite }, 0.2)
            Tween(t._txtStroke, { Transparency = 0.3 }, 0.2)
            t._indicator.Visible = true
            t._pill.Visible = true
            t._pill.BackgroundTransparency = 1
            Tween(t._pill, { BackgroundTransparency = 0.86 }, 0.3)
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
    local txtStroke = Make("UIStroke", { Parent = bgText, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.75 })
    self:_breathe(Make("UIGradient", { Parent = txtStroke, Rotation = 0 }))
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
        if not indicator.Visible then
            Tween(fgText, { TextColor3 = self.Theme.TextWhite }, 0.15)
            Tween(txtStroke, { Transparency = 0.45 }, 0.15)
        end
        Tween(btnScale, { Scale = 1.05 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        Tween(bgText, { Position = UDim2.new(0, 8, 0, 0) }, 0.25, Enum.EasingStyle.Quint)
        Tween(fgText, { Position = UDim2.new(0, 8, 0, 0) }, 0.25, Enum.EasingStyle.Quint)
    end)
    btn.MouseLeave:Connect(function()
        if not indicator.Visible then
            Tween(fgText, { TextColor3 = self.Theme.TextDim }, 0.15)
            Tween(txtStroke, { Transparency = 0.75 }, 0.15)
        end
        Tween(btnScale, { Scale = 1 }, 0.2)
        Tween(bgText, { Position = UDim2.new() }, 0.25, Enum.EasingStyle.Quint)
        Tween(fgText, { Position = UDim2.new() }, 0.25, Enum.EasingStyle.Quint)
    end)
    btn.MouseButton1Click:Connect(function()
        self:_play("Click")
        Tween(btnScale, { Scale = 0.95 }, 0.1)
        task.delay(0.1, function() Tween(btnScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
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
    Make("UIGradient", { Parent = header, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }) })
    win:_cometMark(header, 9, Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0))
    Make("TextLabel", {
        Parent = header, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 28, 0, 0), BackgroundTransparency = 1,
        Text = title, TextColor3 = win.Theme.TextWhite, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
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

--- Section:AddButton("Name", function() end)
function Section:AddButton(name, callback)
    local win = self.Window
    local btn = Make("TextButton", {
        Parent = self.Content, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 0.3, Text = name,
        TextColor3 = win.Theme.TextWhite, Font = Enum.Font.Montserrat, TextSize = 13, AutoButtonColor = false,
    })
    win:_bind(function(t) btn.BackgroundColor3 = t.ToggleOff end)
    Corner(btn, 8)
    Make("UIGradient", { Parent = btn, Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 235)) })
    win:_stroke(btn, 1, 0.2)
    local scale = win:_fx(btn, { Grow = 1.04 })
    btn.MouseButton1Down:Connect(function() Tween(scale, { Scale = 0.94 }, 0.1) end)
    btn.MouseButton1Up:Connect(function() Tween(scale, { Scale = 1.04 }, 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
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
    fill.BackgroundColor3 = Color3.new(1, 1, 1)
    local fillGrad = Make("UIGradient", { Parent = fill })
    win:_bind(function(t) fillGrad.Color = ColorSequence.new(t.Accent, t.AccentLight) end)
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
