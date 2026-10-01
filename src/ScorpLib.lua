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
    -- Default: Cosmic Void — deep purple + electric cyan
    ["Cosmic Void"]   = { Accent = Color3.fromRGB(130, 60, 255),  AccentLight = Color3.fromRGB(0, 210, 255),
                          MainBg = Color3.fromRGB(6, 5, 16), SidebarBg = Color3.fromRGB(4, 3, 11), ToggleOff = Color3.fromRGB(18, 14, 40) },
    ["Nova Pulse"]    = { Accent = Color3.fromRGB(160, 80, 255),  AccentLight = Color3.fromRGB(80, 230, 255),
                          MainBg = Color3.fromRGB(8, 6, 20), SidebarBg = Color3.fromRGB(5, 4, 14), ToggleOff = Color3.fromRGB(22, 16, 48) },
    ["Nebula Blue"]   = { Accent = Color3.fromRGB(60, 130, 255),  AccentLight = Color3.fromRGB(140, 80, 255),
                          MainBg = Color3.fromRGB(5, 8, 22), SidebarBg = Color3.fromRGB(3, 5, 15), ToggleOff = Color3.fromRGB(14, 20, 52) },
    ["Solar Flare"]   = { Accent = Color3.fromRGB(255, 80, 60),   AccentLight = Color3.fromRGB(255, 180, 50),
                          MainBg = Color3.fromRGB(14, 6, 6), SidebarBg = Color3.fromRGB(10, 4, 4), ToggleOff = Color3.fromRGB(32, 12, 12) },
    ["Void Emerald"]  = { Accent = Color3.fromRGB(40, 220, 140),  AccentLight = Color3.fromRGB(100, 255, 200),
                          MainBg = Color3.fromRGB(4, 12, 10), SidebarBg = Color3.fromRGB(3, 8, 7), ToggleOff = Color3.fromRGB(10, 28, 22) },
    ["Silver Surfer"] = { Accent = Color3.fromRGB(160, 180, 220), AccentLight = Color3.fromRGB(80, 210, 255),
                          MainBg = Color3.fromRGB(8, 9, 20), SidebarBg = Color3.fromRGB(5, 6, 14), ToggleOff = Color3.fromRGB(18, 22, 44) },
}
Library.ThemeOrder = { "Cosmic Void", "Nova Pulse", "Nebula Blue", "Solar Flare", "Void Emerald", "Silver Surfer" }

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
    self._keybinds    = {}
    self._kbWatch     = {}
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
        self.ThemeName = Library.Themes[opts.Theme or ""] and opts.Theme or "Cosmic Void"
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
        if self.ToggleKey and input.KeyCode == self.ToggleKey then
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
    local toggleName = (self.ToggleKey and self.ToggleKey.Name) or "None"
    local txt = "[" .. toggleName .. "] Toggle"
    if self.UnloadKey and self.UnloadKey.Name then txt = txt .. "  |  [" .. self.UnloadKey.Name .. "] Unload" end
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

    pcall(function() self.Gui.Enabled = false end)
    if self.Blur then pcall(function() self.Blur.Size = 0 end) end
    local ok = pcall(function()
        Library:CreateSplash({ Image = self.LogoImage, Kind = "bye" }):Play(finish)
    end)
    if not ok then finish() end
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
    self._loadingConfig = true
    for flag, raw in pairs(data) do
        local setter = self._setters[flag]
        if setter then pcall(setter, DecodeFlag(raw)) end
    end
    self._loadingConfig = false
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
        win:_noteKeybinds()
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
            if o.Flag then win.Flags[o.Flag .. "_Key"] = k or false end
        end)
        win:TrackKeybind({
            Name = name,
            Get = function() return bind.Get() end,
            Set = function(k) bind.Set(k) end,
        })
        if o.Flag then
            win.Flags[o.Flag .. "_Key"] = o.Keybind or false
            win._setters[o.Flag .. "_Key"] = function(k) bind.Set(k, true); win.Flags[o.Flag .. "_Key"] = k or false end
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
        if o.Flag then win.Flags[o.Flag] = k or false end
        Fire(o.OnChange, k)
    end)
    local obj = { Frame = row }
    function obj:Set(k, silent)
        bind.Set(k, silent)
        if o.Flag then win.Flags[o.Flag] = k or false end
        if silent then Fire(o.OnChange, k) end
    end
    function obj:Get() return bind.Get() end
    win:_connect(UserInputService.InputBegan, function(input, gp)
        local k = bind.Get()
        if win._binding or gp or not k or input.KeyCode ~= k then return end
        Fire(o.Callback, k)
    end)
    if o.Flag then
        win.Flags[o.Flag] = o.Default or false
        win._setters[o.Flag] = function(k) obj:Set(k, true) end
    end
    win:TrackKeybind({
        Name = name,
        Get = function() return bind.Get() end,
        Set = function(k) obj:Set(k) end,
    })
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


function Window:TrackKeybind(entry)
    self._keybinds[#self._keybinds + 1] = entry
    self:_noteKeybinds()
    return entry
end

function Window:OnKeybindsChanged(fn)
    self._kbWatch[#self._kbWatch + 1] = fn
end

function Window:_noteKeybinds()
    if self._kbQueued then return end
    self._kbQueued = true
    task.defer(function()
        self._kbQueued = false
        if self.Destroyed then return end
        local watch = self._kbWatch
        for i = 1, #watch do
            pcall(watch[i])
        end
    end)
end

function Section:AddBindRow(entry)
    local win = self.Window
    local row = Row(self, 32)
    RowLabel(win, row, entry.Name, -150)
    local keyLbl = Make("TextLabel", {
        Parent = row, Size = UDim2.fromOffset(72, 20), Position = UDim2.new(1, -108, 0.5, -10),
        BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    win:_bind(function(t) keyLbl.TextColor3 = t.TextDim end)
    local key = entry.Get()
    keyLbl.Text = (key and key.Name) and ("[ " .. key.Name .. " ]") or "[ None ]"
    local clear = Make("TextButton", {
        Parent = row, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -28, 0.5, -12),
        BackgroundTransparency = 0.3, Text = "✕", TextColor3 = win.Theme.TextWhite,
        Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = false,
    })
    win:_bind(function(t) clear.BackgroundColor3 = t.ToggleOff end)
    Corner(clear, 6)
    win:_fx(clear, { Grow = 1.08 })
    clear.MouseButton1Click:Connect(function()
        win:_play("Click")
        entry.Set(nil)
    end)
    return { Frame = row }
end

function Window:MountKeybindTab(tab)
    local sec = tab:CreateSection("Assigned keys", true)
    sec:AddLabel("Press X to clear a key completely. The control stays; only that key is removed.", { Wrap = true, Color = self.Theme.TextDim })
    local empty = sec:AddLabel("No keys assigned yet.", { Color = self.Theme.TextDim })
    local rows = {}
    local function rebuild()
        for i = 1, #rows do
            if rows[i].Frame then rows[i].Frame:Destroy() end
        end
        rows = {}
        local n = 0
        local list = self._keybinds
        for i = 1, #list do
            local entry = list[i]
            local key = entry.Get()
            if key and key.Name then
                n = n + 1
                rows[n] = sec:AddBindRow(entry)
            end
        end
        empty.Frame.Visible = n == 0
        empty.Frame.Size = UDim2.new(1, 0, 0, n == 0 and 20 or 0)
    end
    self:OnKeybindsChanged(rebuild)
    rebuild()
end

-- ───────────────────────────────────────────────────────────────────────────
--  Standalone popout panel — a second, independent window with its own drag
--  and its own show/hide, that still accepts :CreateSection(...) exactly like
--  a sidebar Tab does. Use this for anything that deserves its own window
--  instead of being buried in the sidebar (e.g. the tag editor).
-- ───────────────────────────────────────────────────────────────────────────
function Window:CreatePopout(opts)
    opts = opts or {}
    local win = self
    local size = opts.Size or UDim2.fromOffset(460, 560)

    local frame = Make("Frame", {
        Name = opts.Name or "Popout", Parent = self.Gui, Size = size,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = opts.Position or UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 0.05, ClipsDescendants = true, Active = true, Visible = false, ZIndex = 80,
    })
    win:_bind(function(t) frame.BackgroundColor3 = t.MainBg end)
    local scale = Make("UIScale", { Parent = frame, Scale = 0 })
    Corner(frame, 14)
    win:_stroke(frame, 1, 0.35)

    local head = Make("Frame", { Parent = frame, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 81 })
    Make("TextLabel", {
        Parent = head, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 16, 0, 0), BackgroundTransparency = 1,
        Text = opts.Title or "Panel", TextColor3 = self.Theme.TextWhite, Font = Enum.Font.GothamBlack, TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 81,
    })
    local closeBtn = Make("TextButton", {
        Parent = head, Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -36, 0.5, -14), BackgroundTransparency = 0.3,
        Text = "✕", TextColor3 = self.Theme.TextWhite, Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = false, ZIndex = 81,
    })
    win:_bind(function(t) closeBtn.BackgroundColor3 = t.ToggleOff end)
    Corner(closeBtn, 8)
    win:_fx(closeBtn, { Grow = 1.08 })
    win:_drag(head, frame)

    local page = Make("ScrollingFrame", {
        Parent = frame, Size = UDim2.new(1, -12, 1, -50), Position = UDim2.new(0, 6, 0, 46), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 80,
    })
    win:_bind(function(t) page.ScrollBarImageColor3 = t.Accent end)
    Make("UIPadding", { Parent = page, PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 20) })
    Make("UIListLayout", { Parent = page, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })

    -- Duck-types as a Tab (same .Window / .Page shape) so every existing Section:Add*
    -- control works completely unmodified inside a popout.
    local popout = setmetatable({ Window = win, Name = opts.Title or "Panel", Page = page }, Tab)
    popout.Visible = false
    popout.Frame = frame

    local function setVisible(v)
        v = v and true or false
        if v == popout.Visible then return end
        popout.Visible = v
        if v then
            win:_play("Click")
            frame.Visible = true
            Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        else
            Tween(scale, { Scale = 0 }, 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
            task.delay(0.25, function() if not popout.Visible then frame.Visible = false end end)
        end
        if opts.OnToggle then Fire(opts.OnToggle, v) end
    end
    closeBtn.MouseButton1Click:Connect(function() win:_play("Click"); setVisible(false) end)

    function popout:Show() setVisible(true) end
    function popout:Hide() setVisible(false) end
    function popout:Toggle() setVisible(not popout.Visible) end
    return popout
end

-- ───────────────────────────────────────────────────────────────────────────
--  Persistent top info bar — player count (with a floating +1/-1 on join/leave),
--  ping, fps, and a row of icon buttons. Lives outside Main, so it's visible
--  whether the main panel is open or closed (mirrors the always-on bar Mois7-
--  style hubs use). Icon actions are supplied by the caller via opts, so this
--  stays generic — script.lua decides what the gear / nametag / discord icons do.
-- ───────────────────────────────────────────────────────────────────────────
function Window:CreateInfoBar(opts)
    opts = opts or {}
    local win = self
    local ok, Stats = pcall(function() return game:GetService("Stats") end)
    Stats = ok and Stats or nil

    local bar = Make("Frame", {
        Name = "InfoBar", Parent = self.Gui, Size = UDim2.fromOffset(0, 52), AutomaticSize = Enum.AutomaticSize.X,
        AnchorPoint = Vector2.new(0.5, 0), Position = opts.Position or UDim2.new(0.5, 0, 0, 16),
        BackgroundColor3 = Color3.fromRGB(8, 6, 18), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 70,
    })
    Round(bar)
    local shade = Make("UIGradient", {
        Parent = bar, Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(28, 22, 48), Color3.fromRGB(8, 6, 16)),
    })
    local rim = Make("UIStroke", {
        Parent = bar, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1,
        Color = Color3.new(1, 1, 1), Transparency = 0.82,
    })
    local sheen = Make("Frame", {
        Parent = bar, Size = UDim2.new(1, -72, 0, 1), Position = UDim2.new(0, 36, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 72,
    })

    local row = Make("Frame", {
        Parent = bar, Size = UDim2.fromOffset(0, 52), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 71,
    })
    Make("UIPadding", { Parent = row, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
    Make("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local order = 0
    local function nextOrder()
        order = order + 1
        return order
    end

    local function chip()
        local holder = Make("Frame", {
            Parent = row, LayoutOrder = nextOrder(), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = 71,
        })
        Corner(holder, 10)
        Make("UIPadding", { Parent = holder, PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) })
        Make("UIListLayout", {
            Parent = holder, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
        })
        return holder
    end

    local function readout(parent, width, layout)
        return Make("TextLabel", {
            Parent = parent, LayoutOrder = layout, Size = UDim2.fromOffset(width, 34), BackgroundTransparency = 1,
            Text = "—", TextColor3 = win.Theme.TextWhite, Font = Enum.Font.GothamBold, TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72,
        })
    end

    local function unit(parent, text, layout)
        local label = Make("TextLabel", {
            Parent = parent, LayoutOrder = layout, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1, Text = text, Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 72,
        })
        win:_bind(function(t) label.TextColor3 = t.TextDim end)
        return label
    end

    win:_bind(function(t)
        local base = t.MainBg or Color3.fromRGB(8, 6, 18)
        local side = t.SidebarBg or base
        bar.BackgroundColor3 = base
        shade.Color = ColorSequence.new(side:Lerp(Color3.new(1, 1, 1), 0.12), base)
        rim.Color = t.TextWhite or Color3.new(1, 1, 1)
        sheen.BackgroundColor3 = t.TextWhite or Color3.new(1, 1, 1)
    end)

    -- Player count, with a floating +1 / -1 whenever someone joins or leaves.
    local countHolder = chip()
    local dot = Make("Frame", {
        Parent = countHolder, LayoutOrder = 1, Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = win.Theme.AccentLight, BorderSizePixel = 0, ZIndex = 72,
    })
    Round(dot)
    win:_bind(function(t)
        countHolder.BackgroundColor3 = t.ToggleOff or t.SidebarBg
        dot.BackgroundColor3 = t.AccentLight
    end)
    local countLabel = readout(countHolder, 28, 2)
    local function bump(delta)
        local color = delta > 0 and win.Theme.Success or win.Theme.Danger
        local origin = countHolder.AbsolutePosition - bar.AbsolutePosition
        local x = origin.X + countHolder.AbsoluteSize.X * 0.5
        local badge = Make("TextLabel", {
            Parent = bar, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, origin.Y),
            Size = UDim2.fromOffset(28, 14), BackgroundTransparency = 1, Text = (delta > 0 and "+1" or "-1"),
            TextColor3 = color, Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 74,
        })
        Tween(badge, { Position = UDim2.fromOffset(x, origin.Y - 14), TextTransparency = 1 }, 0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            .Completed:Connect(function() badge:Destroy() end)
    end
    local function refreshCount() countLabel.Text = tostring(#Players:GetPlayers()) end
    refreshCount()
    win:_connect(Players.PlayerAdded, function() refreshCount(); bump(1) end)
    win:_connect(Players.PlayerRemoving, function()
        bump(-1)
        task.defer(refreshCount)
    end)

    -- Ping: three bars that fill in as the connection gets better.
    local pingHolder = chip()
    win:_bind(function(t) pingHolder.BackgroundColor3 = t.ToggleOff or t.SidebarBg end)
    local barsHost = Make("Frame", {
        Parent = pingHolder, LayoutOrder = 1, Size = UDim2.fromOffset(13, 12), BackgroundTransparency = 1, ZIndex = 72,
    })
    local pingBars = {}
    local barHeights = { 4, 8, 12 }
    for i = 1, 3 do
        local h = barHeights[i]
        pingBars[i] = Make("Frame", {
            Parent = barsHost, Size = UDim2.fromOffset(3, h), Position = UDim2.new(0, (i - 1) * 5, 1, -h),
            BackgroundColor3 = Color3.fromRGB(120, 126, 150), BackgroundTransparency = 0.55,
            BorderSizePixel = 0, ZIndex = 72,
        })
        Corner(pingBars[i], 1)
    end
    local pingLabel = readout(pingHolder, 36, 2)
    unit(pingHolder, "ms", 3)

    local fpsHolder = chip()
    win:_bind(function(t) fpsHolder.BackgroundColor3 = t.ToggleOff or t.SidebarBg end)
    local fpsLabel = readout(fpsHolder, 26, 1)
    unit(fpsHolder, "fps", 2)

    local function paintPing(ms)
        local lit, color = 1, win.Theme.Danger
        if ms <= 70 then
            lit, color = 3, win.Theme.Success
        elseif ms <= 140 then
            lit, color = 2, win.Theme.Warning
        end
        pingLabel.TextColor3 = color
        for i = 1, 3 do
            pingBars[i].BackgroundColor3 = color
            pingBars[i].BackgroundTransparency = i <= lit and 0 or 0.72
        end
    end

    local function paintFps(fps)
        local color = win.Theme.Danger
        if fps >= 55 then
            color = win.Theme.Success
        elseif fps >= 30 then
            color = win.Theme.Warning
        end
        fpsLabel.TextColor3 = color
    end

    do
        local frames, acc = 0, 0
        win:_connect(RunService.RenderStepped, function(dt)
            frames, acc = frames + 1, acc + dt
            if acc >= 0.5 then
                local fps = math.floor(frames / acc + 0.5)
                fpsLabel.Text = tostring(fps)
                paintFps(fps)
                frames, acc = 0, 0
            end
        end)
        task.spawn(function()
            while bar.Parent do
                local pingOk, ping = false, nil
                if Stats then
                    pingOk, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                end
                if pingOk and ping then
                    local ms = math.floor(ping + 0.5)
                    pingLabel.Text = tostring(ms)
                    paintPing(ms)
                else
                    pingLabel.Text = "—"
                    pingLabel.TextColor3 = win.Theme.TextDim
                end
                task.wait(1)
            end
        end)
    end

    local divider = Make("Frame", {
        Parent = row, LayoutOrder = nextOrder(), Size = UDim2.fromOffset(1, 22),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 71,
    })
    win:_bind(function(t) divider.BackgroundColor3 = t.AccentLight or Color3.new(1, 1, 1) end)

    local function mark(parent, size, pos)
        return Make("Frame", {
            Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size,
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false, ZIndex = 73,
        })
    end

    local function iconBtn(draw, onClick)
        local b = Make("TextButton", {
            Parent = row, LayoutOrder = nextOrder(), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 0.2,
            Text = "", AutoButtonColor = false, ZIndex = 71,
        })
        Round(b)
        local edge = Make("UIStroke", {
            Parent = b, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = 0.72,
        })
        win:_bind(function(t)
            b.BackgroundColor3 = t.ToggleOff or t.SidebarBg
            edge.Color = t.TextWhite or Color3.new(1, 1, 1)
        end)
        draw(b)
        win:_fx(b, { Grow = 1.08 })
        b.MouseButton1Click:Connect(function() win:_play("Click"); Fire(onClick) end)
        return b
    end

    iconBtn(function(b)
        local hub = mark(b, UDim2.fromOffset(8, 8), UDim2.fromScale(0.5, 0.5))
        hub.BackgroundTransparency = 1
        Round(hub)
        Make("UIStroke", { Parent = hub, Thickness = 1.5, Color = Color3.new(1, 1, 1) })
        for i = 0, 5 do
            local a = math.rad(i * 60)
            local tooth = mark(b, UDim2.fromOffset(3, 3), UDim2.new(0.5, math.floor(math.cos(a) * 7 + 0.5), 0.5, math.floor(math.sin(a) * 7 + 0.5)))
            Round(tooth)
        end
    end, opts.OnSettings or function() win:Toggle(true) end)

    if opts.OnGlobe then
        iconBtn(function(b)
            local ring = mark(b, UDim2.fromOffset(14, 14), UDim2.fromScale(0.5, 0.5))
            ring.BackgroundTransparency = 1
            Round(ring)
            Make("UIStroke", { Parent = ring, Thickness = 1.3, Color = Color3.new(1, 1, 1) })
            mark(b, UDim2.fromOffset(12, 1), UDim2.fromScale(0.5, 0.5))
            mark(b, UDim2.fromOffset(1, 12), UDim2.fromScale(0.5, 0.5))
        end, opts.OnGlobe)
    end

    if opts.OnDiscord then
        iconBtn(function(b)
            for i = -1, 1 do
                local d = mark(b, UDim2.fromOffset(3, 3), UDim2.new(0.5, i * 5, 0.5, 0))
                Round(d)
            end
        end, opts.OnDiscord)
    end

    if opts.OnNametag then
        iconBtn(function(b)
            local head = mark(b, UDim2.fromOffset(7, 7), UDim2.new(0.5, 0, 0.5, -5))
            Round(head)
            local body = mark(b, UDim2.fromOffset(14, 7), UDim2.new(0.5, 0, 0.5, 5))
            Corner(body, 4)
        end, opts.OnNametag)
    end

    local api = { Frame = bar }
    function api.Destroy() pcall(function() bar:Destroy() end) end
    return api
end

-- ───────────────────────────────────────────────────────────────────────────
-- Full-screen card used when the script starts and when the menu is unloaded.
-- The mark is the Scorp logo image (white S + wordmark). Kind "load" is the
-- progress card; Kind "bye" is the goodbye card.

local SCORP_LOGO_B64 = [=[/9j/4AAQSkZJRgABAQAAAQABAAD/4gHYSUNDX1BST0ZJTEUAAQEAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAH4AABAAEAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADb/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAKqBAADASIAAhEBAxEB/8QAHgABAAICAgMBAAAAAAAAAAAAAAEJAgoHCAMFBgT/xABqEAACAQIDBQMFBwsLEAYIBwAAAQIDBAUGEQcIITFBCRITUVJhcdMZIjKBldHSFBYXGDdCV4WRlJYVIzNHVFZ1hpKh1CQ0NUNFRlViY3J0hLGytME2RHaCk8IlKDhTosPw8SYnZWaDs+H/xAAVAQEBAAAAAAAAAAAAAAAAAAAAAf/EABURAQEAAAAAAAAAAAAAAAAAAAAR/9oADAMBAAIRAxEAPwCqoAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAaAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHIAAAAAAAAAAANAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANQAAAAAAAAAAAAAAAAAAAAAAAAAA0AAaAagAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANAAAABAAAAAAAAAAAAAAAAAAAAAACegAAIAAAAAAAAAAAAAAAAAAAAAAAAAFoAAAAADQAAAAAAAAAAAAAAAAAAAAAA0AAAAB6gAAAAagAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHMAAAAAAAAAAAAAAAAAAAGvAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYAAAAAAAAAAAAAAAAAAAAAA9QAAAAAAAAAAAAAAAHMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOnpAAAAAAAAAAAAAAAAAAAAAAGAAAAAAAAAGgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACYAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADUAAAAAAAAAAAAAAAAANAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAmXMhdQAAAALqEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdAAAXMAAAAAAAAAAAAAAAAAAAAAAABAAAAAXMdAAQC5gAHzAAAMAB0AAAAAAuYAALmAAfMAAAAAAAAAAAAAAAAAAB0AADowAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdAAAAAAAAAAAAAAAAAAAAAAAf//Z]=]

local function scorpLogoAsset()
    if type(writefile) ~= "function" then return nil end
    local data = SCORP_LOGO_B64
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local map = {}
    for i = 1, #chars do map[chars:sub(i, i)] = i - 1 end
    local out, n, buffer, bits = {}, 0, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c == "=" then break end
        local v = map[c]
        if v then
            buffer = buffer * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local byte = math.floor(buffer / (2 ^ bits)) % 256
                n = n + 1
                out[n] = string.char(byte)
                buffer = buffer % (2 ^ bits)
            end
        end
    end
    local raw = table.concat(out)
    if #raw < 32 then return nil end
    if not pcall(writefile, "ScorpLogo.jpg", raw) then return nil end
    local function asset(fn)
        if type(fn) ~= "function" then return nil end
        local ok, id = pcall(fn, "ScorpLogo.jpg")
        if ok and type(id) == "string" and id ~= "" then return id end
        return nil
    end
    return asset(getcustomasset) or asset(getsynasset)
end

function Library:CreateSplash(opts)
    opts = opts or {}
    local kind = opts.Kind == "bye" and "bye" or "load"
    local gui = Make("ScreenGui", {
        Name = kind == "bye" and "ScorpGoodbye" or "ScorpLoading",
        ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1200,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    AttachGui(gui)

    local canvas
    pcall(function()
        canvas = Make("CanvasGroup", {
            Name = "Card", Parent = gui, Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0,
            GroupTransparency = 1, BorderSizePixel = 0,
        })
    end)
    local root = canvas or Make("Frame", {
        Name = "Card", Parent = gui, Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
    })

    local logo = Make("ImageLabel", {
        Parent = root, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 0),
        Size = UDim2.fromOffset(460, 260), BackgroundTransparency = 1,
        Image = type(opts.Image) == "string" and opts.Image or "",
        ScaleType = Enum.ScaleType.Fit, Visible = type(opts.Image) == "string" and opts.Image ~= "",
    })
    local fallback = Make("TextLabel", {
        Parent = root, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 0),
        Size = UDim2.fromOffset(420, 80), BackgroundTransparency = 1,
        Text = "S  C  O  R  P", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBlack, TextSize = 42, Visible = not logo.Visible,
    })

    local kicker = Make("TextLabel", {
        Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.38, 150),
        Size = UDim2.fromOffset(320, 18), BackgroundTransparency = 1,
        Text = kind == "load" and "LOADING" or "",
        TextColor3 = Color3.fromRGB(170, 170, 176), Font = Enum.Font.Gotham, TextSize = 13,
    })
    local status = Make("TextLabel", {
        Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.38, 172),
        Size = UDim2.fromOffset(420, 28), BackgroundTransparency = 1,
        Text = kind == "bye" and "G  O  O  D  B  Y  E" or "Preparing client",
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham, TextSize = kind == "bye" and 22 or 16,
    })
    local track = Make("Frame", {
        Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.38, 214),
        Size = UDim2.fromOffset(220, 2), BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.75, BorderSizePixel = 0, Visible = kind == "load",
    })
    local fill = Make("Frame", {
        Parent = track, Size = UDim2.new(0.08, 0, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    })

    if canvas then
        Tween(canvas, { GroupTransparency = 0 }, 0.35)
    else
        Tween(root, { BackgroundTransparency = 0 }, 0.35)
    end

    local api = { Gui = gui }
    function api:SetImage(id)
        if type(id) ~= "string" or id == "" then return end
        logo.Image = id
        logo.Visible = true
        fallback.Visible = false
    end
    local function fadeOut(done)
        if canvas then
            Tween(canvas, { GroupTransparency = 1 }, 0.45)
        else
            Tween(root, { BackgroundTransparency = 1 }, 0.45)
            Tween(fallback, { TextTransparency = 1 }, 0.45)
            Tween(kicker, { TextTransparency = 1 }, 0.45)
            Tween(status, { TextTransparency = 1 }, 0.45)
            Tween(logo, { ImageTransparency = 1 }, 0.45)
            Tween(track, { BackgroundTransparency = 1 }, 0.45)
            Tween(fill, { BackgroundTransparency = 1 }, 0.45)
        end
        task.delay(0.5, function()
            pcall(function() gui:Destroy() end)
            if done then done() end
        end)
    end
    function api:Play(done)
        task.spawn(function()
            if kind == "bye" then
                task.wait(1.35)
                fadeOut(done)
                return
            end
            local steps = {
                { text = "Preparing client", progress = 0.38, hold = 0.45 },
                { text = "Loading interface", progress = 0.74, hold = 0.4 },
                { text = "Ready", progress = 1, hold = 0.28 },
            }
            for i = 1, #steps do
                status.Text = steps[i].text
                Tween(fill, { Size = UDim2.new(steps[i].progress, 0, 1, 0) }, 0.35)
                task.wait(steps[i].hold)
            end
            fadeOut(done)
        end)
    end
    task.spawn(function()
        if logo.Image ~= "" then return end
        local id = scorpLogoAsset()
        if id then api:SetImage(id) end
    end)
    return api
end

Library.Window, Library.Tab, Library.Section = Window, Tab, Section
return Library
