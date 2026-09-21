-- ───────────────────────────────────────────────────────────────────────────
--  Scorp nametags
--
--  This file is pulled into src/script.lua by the build (--@include) and ends
--  with `return Nametags`. Everything visual is in the DESIGN block below — edit
--  the numbers there and re-run the build (the server also rebuilds on its own).
--
--  How it works:
--    · Every ~10 s the client POSTs to  /api/nametags/sync  and gets back the
--      other Scorp users in THIS Roblox server, with the role the SERVER assigned
--      (clients can never pick their own role).
--    · Each one gets a BillboardGui above their head. It's only drawn on your
--      screen, and only for people who are also running Scorp.
--
--  Lua 5.1 syntax only (the obfuscator parses 5.1) — no `continue`, `+=`, or types.
-- ───────────────────────────────────────────────────────────────────────────

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService  = game:GetService("TextService")
local HttpService  = game:GetService("HttpService")
local CoreGui      = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Nametags = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  DESIGN
-- ═══════════════════════════════════════════════════════════════════════════
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local DESIGN = {
    Height        = 42,     -- card height (px)
    Padding       = 10,     -- inner left/right padding
    Badge         = 30,     -- round emblem diameter
    Gap           = 9,      -- emblem → text gap
    Corner        = 13,     -- card corner radius
    StrokeSize    = 2,      -- animated border thickness
    TitleSize     = 15,
    NameSize      = 12,
    TitleFont     = Enum.Font.GothamBold,
    NameFont      = Enum.Font.Gotham,
    Lift          = 2.9,    -- studs above the head
    SweepSeconds  = 3.4,    -- one lap of the light around the border
    CardBg        = rgb(8, 10, 22),   -- deep-space navy (every role blends toward this)
    CardBgBottom  = rgb(5, 6, 14),
    NameColor     = rgb(150, 164, 190),
    White         = rgb(255, 255, 255),
}

-- One accent colour per role; everything else (title colour, emblem fill, card
-- tint, glow) is derived from it so a new role is a one-line addition.
local STYLES = {
    owner     = { accent = rgb(255, 196,  64), glyph = "👑" },
    developer = { accent = rgb(150, 120, 255), glyph = "⚡" },
    admin     = { accent = rgb(255,  88, 110), glyph = "🛡️" },
    moderator = { accent = rgb(255, 150,  64), glyph = "🔨" },
    support   = { accent = rgb( 96, 214, 255), glyph = "🎧" },
    vip       = { accent = rgb(255, 110, 214), glyph = "💎" },
    member    = { accent = rgb(168, 186, 214), glyph = "🌙" },
}
-- Title shown when the server doesn't send a custom label (also used by Preview)
local LABELS = {
    owner = "Owner", developer = "Developer", admin = "Admin", moderator = "Moderator",
    support = "Support", vip = "VIP", member = "Member",
}
Nametags.STYLES = STYLES
Nametags.DESIGN = DESIGN

local function styleFor(role)
    local s = STYLES[role] or STYLES.member
    if not s.light then
        s.light = s.accent:Lerp(DESIGN.White, 0.35)   -- title text
        s.dark  = s.accent:Lerp(rgb(0, 0, 0), 0.82)   -- emblem fill
        s.tint  = DESIGN.CardBg:Lerp(s.accent, 0.13)  -- top of the card
    end
    return s
end

-- ═══════════════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════════════
local S = {
    Enabled     = true,
    ShowSelf    = true,
    ShowMembers = true,
    Avatars     = true,
    AlwaysOnTop = true,
    MaxDistance = 150,
}
Nametags.Settings = S

local cfg = nil          -- { ctx, request, server, onRevoked }
local running = false
local roster = {}        -- [userId] = { userId, username, displayName, role, label }
local tags = {}          -- [userId] = { gui, head, key, tween }
local thumbs = {}        -- [userId] = rbxthumb content string
local preview = nil      -- { role, label } local-only override for your own tag
local holder = nil

local function getHolder()
    if holder and holder.Parent then return holder end
    local parent = nil
    if type(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then parent = p end
    end
    if not parent then parent = CoreGui end
    local ok, folder = pcall(function()
        local f = Instance.new("Folder")
        f.Name = "ScorpTags"
        f.Parent = parent
        return f
    end)
    if ok and folder and folder.Parent then
        holder = folder
    else
        holder = LocalPlayer:WaitForChild("PlayerGui")
    end
    return holder
end

-- ═══════════════════════════════════════════════════════════════════════════
--  TAG BUILDER
-- ═══════════════════════════════════════════════════════════════════════════
local function textWidth(text, size, font)
    local ok, v = pcall(function()
        return TextService:GetTextSize(text, size, font, Vector2.new(600, 60))
    end)
    if ok and v then return v.X end
    return #text * size * 0.58
end

local function make(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function loadAvatar(userId, image, glyph)
    if not S.Avatars then return end
    task.spawn(function()
        local content = thumbs[userId]
        if not content then
            local ok, result = pcall(function()
                return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
            end)
            if ok and result then
                content = result
                thumbs[userId] = result
            end
        end
        if content and image.Parent then
            image.Image = content
            image.Visible = true
            glyph.Visible = false
        end
    end)
end

local function buildTag(userId, info, head)
    local D = DESIGN
    local style = styleFor(info.role)
    local title = tostring(info.label or info.role or "Member")
    local name  = tostring(info.displayName or info.username or "")

    local textW = math.max(textWidth(title, D.TitleSize, D.TitleFont), textWidth(name, D.NameSize, D.NameFont))
    local cardW = math.clamp(D.Padding + D.Badge + D.Gap + textW + D.Padding + 4, 120, 300)
    local cardH = D.Height
    local margin = 10 -- room around the card for the glow

    local gui = make("BillboardGui", {
        Name = "ScorpTag",
        Adornee = head,
        Size = UDim2.fromOffset(cardW + margin * 2, cardH + margin * 2),
        StudsOffset = Vector3.new(0, D.Lift, 0),
        AlwaysOnTop = S.AlwaysOnTop,
        MaxDistance = S.MaxDistance,
        LightInfluence = 0,
        Active = false,
    })

    -- soft outer glow
    local glow = make("Frame", {
        Name = "Glow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(cardW + 6, cardH + 6),
        BackgroundTransparency = 1,
    }, gui)
    make("UICorner", { CornerRadius = UDim.new(0, D.Corner + 3) }, glow)
    make("UIStroke", { Thickness = 5, Color = style.accent, Transparency = 0.82 }, glow)

    -- card
    local card = make("Frame", {
        Name = "Card",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(cardW, cardH),
        BackgroundColor3 = D.White,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
    }, gui)
    make("UICorner", { CornerRadius = UDim.new(0, D.Corner) }, card)
    make("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(style.tint, D.CardBgBottom),
    }, card)

    -- border with a light that travels around it
    local stroke = make("UIStroke", {
        Thickness = D.StrokeSize,
        Color = D.White,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, card)
    local sweep = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, style.accent),
            ColorSequenceKeypoint.new(0.42, style.accent),
            ColorSequenceKeypoint.new(0.5, D.White),
            ColorSequenceKeypoint.new(0.58, style.accent),
            ColorSequenceKeypoint.new(1, style.accent),
        }),
    }, stroke)
    local tween = TweenService:Create(
        sweep,
        TweenInfo.new(D.SweepSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        { Rotation = 360 }
    )
    tween:Play()

    -- round emblem (role glyph, replaced by the player's headshot once it loads)
    local badge = make("Frame", {
        Name = "Badge",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, D.Padding, 0.5, 0),
        Size = UDim2.fromOffset(D.Badge, D.Badge),
        BackgroundColor3 = style.dark,
        BorderSizePixel = 0,
    }, card)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
    make("UIStroke", { Thickness = 1.5, Color = style.accent, Transparency = 0.1 }, badge)
    local glyph = make("TextLabel", {
        Name = "Glyph",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = style.glyph,
        TextSize = 16,
        TextColor3 = style.light,
        Font = Enum.Font.GothamBold,
    }, badge)
    local avatar = make("ImageLabel", {
        Name = "Avatar",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        Visible = false,
    }, badge)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
    loadAvatar(userId, avatar, glyph)

    -- text
    local textLeft = D.Padding + D.Badge + D.Gap
    local titleLabel = make("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(textLeft, 5),
        Size = UDim2.new(1, -(textLeft + D.Padding), 0, 19),
        BackgroundTransparency = 1,
        Text = title,
        TextSize = D.TitleSize,
        Font = D.TitleFont,
        TextColor3 = style.light,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)
    make("UIStroke", {
        Thickness = 1, Color = style.accent, Transparency = 0.72,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
    }, titleLabel)
    make("TextLabel", {
        Name = "Name",
        Position = UDim2.fromOffset(textLeft, 23),
        Size = UDim2.new(1, -(textLeft + D.Padding), 0, 14),
        BackgroundTransparency = 1,
        Text = name,
        TextSize = D.NameSize,
        Font = D.NameFont,
        TextColor3 = D.NameColor,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)

    gui.Parent = getHolder()
    return gui, tween
end

-- ═══════════════════════════════════════════════════════════════════════════
--  LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════
local function removeTag(userId)
    local t = tags[userId]
    if not t then return end
    tags[userId] = nil
    if t.tween then pcall(function() t.tween:Cancel() end) end
    if t.gui then pcall(function() t.gui:Destroy() end) end
end

local function tagKey(info)
    return tostring(info.role) .. "|" .. tostring(info.label) .. "|" .. tostring(info.displayName)
end

local function getHead(player)
    local ch = player.Character
    if not ch then return nil end
    return ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
end

local function infoFor(userId)
    if preview and userId == LocalPlayer.UserId then
        return {
            userId = userId,
            username = LocalPlayer.Name,
            displayName = LocalPlayer.DisplayName,
            role = preview.role,
            label = preview.label,
        }
    end
    return roster[userId]
end

local function applyTag(userId)
    local info = infoFor(userId)
    local player = Players:GetPlayerByUserId(userId)
    if not info or not player or not S.Enabled then return removeTag(userId) end
    if userId == LocalPlayer.UserId and not S.ShowSelf then return removeTag(userId) end
    if info.role == "member" and not S.ShowMembers then return removeTag(userId) end

    local head = getHead(player)
    if not head then return removeTag(userId) end

    local key = tagKey(info)
    local t = tags[userId]
    if t and t.head == head and t.key == key and t.gui.Parent then
        t.gui.MaxDistance = S.MaxDistance
        t.gui.AlwaysOnTop = S.AlwaysOnTop
        return
    end

    removeTag(userId)
    local ok, gui, tween = pcall(buildTag, userId, info, head)
    if ok and gui then
        tags[userId] = { gui = gui, head = head, key = key, tween = tween }
    end
end

local function render()
    for userId in pairs(tags) do
        if not infoFor(userId) then removeTag(userId) end
    end
    for userId in pairs(roster) do applyTag(userId) end
    if preview then applyTag(LocalPlayer.UserId) end
end

local function sync()
    if not cfg then return end
    local ctx = cfg.ctx
    local ok, res = pcall(cfg.request, {
        Url = cfg.server .. "/api/nametags/sync",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. tostring(ctx.token),
        },
        Body = HttpService:JSONEncode({
            jobId = game.JobId,
            placeId = game.PlaceId,
            displayName = LocalPlayer.DisplayName,
        }),
    })
    if not ok or type(res) ~= "table" then return end

    local status = res.StatusCode or 0
    if status == 403 then
        if cfg.onRevoked then cfg.onRevoked() end
        return
    end
    if status ~= 200 or not res.Body then return end -- 401 = token being renewed by the loader; retry next tick

    local decoded, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not decoded or type(data) ~= "table" or type(data.users) ~= "table" then return end

    local fresh = {}
    for _, u in ipairs(data.users) do
        local id = tonumber(u.userId)
        if id then fresh[id] = u end
    end
    roster = fresh
    render()
end

--- Nametags.Start({ ctx = ctx, request = fn, server = "https://...", onRevoked = fn })
function Nametags.Start(options)
    if running then return end
    cfg = options
    running = true
    task.spawn(function()
        while running do
            sync()
            for _ = 1, 10 do           -- sync every ~10 s …
                if not running then return end
                task.wait(1)
                render()               -- … but repair tags (respawns, toggles) every second
            end
        end
    end)
end

function Nametags.Refresh()
    if running then task.spawn(sync) end
end

--- Change a setting and redraw. Nametags.Set("MaxDistance", 200)
function Nametags.Set(name, value)
    S[name] = value
    if name == "Avatars" then
        for userId in pairs(tags) do removeTag(userId) end
    end
    render()
end

--- Local-only preview of a style on your own tag. Nametags.Preview("owner") … Nametags.Preview(nil)
function Nametags.Preview(role, label)
    if role and STYLES[role] then
        preview = { role = role, label = label or LABELS[role] }
    else
        preview = nil
        removeTag(LocalPlayer.UserId)
    end
    render()
end

function Nametags.Stop()
    if not running and not cfg then return end
    running = false
    local c = cfg
    cfg = nil
    for userId in pairs(tags) do removeTag(userId) end
    roster = {}
    if holder then pcall(function() holder:Destroy() end) holder = nil end
    if c then
        pcall(c.request, {
            Url = c.server .. "/api/nametags/leave",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. tostring(c.ctx.token),
            },
            Body = "{}",
        })
    end
end

return Nametags
