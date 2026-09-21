-- ───────────────────────────────────────────────────────────────────────────
--  Scorp nametags
--
--  This file is pulled into src/script.lua by the build (--@include) and ends
--  with `return Nametags`.
--
--  DESIGN DATA comes from --@tagdata below, which the build replaces with
--  TAGDATA generated from src/tagconfig.js: role defaults + per-role presets.
--  That's the SAME data the Discord /tag command validates against and shows
--  in its embed, so a staff member's `/tag set 123 primary #ff8800` and what
--  renders above that player's head can never disagree.
--
--  How a player's tag is built:
--      effective = TAGDATA.defaults  +  TAGDATA.presets[role]  +  their own
--                  server-assigned overrides (only what a staff member changed)
--  Only the overrides travel over the wire (POST /api/nametags/sync), so most
--  players — who have no custom design — cost almost nothing extra.
--
--  How it works:
--    · Every ~10 s the client POSTs to  /api/nametags/sync  and gets back the
--      other Scorp users in THIS Roblox server, with the role/label/overrides
--      the SERVER assigned (clients can never pick their own design).
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
--  DESIGN DATA  (generated — see the header comment above)
-- ═══════════════════════════════════════════════════════════════════════════
--@tagdata

local WHITE = Color3.fromRGB(255, 255, 255)

local function toColor3(hex)
    hex = tostring(hex or "#ffffff"):gsub("^#", "")
    if #hex ~= 6 then return Color3.fromRGB(255, 255, 255) end
    return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16) or 255, tonumber(hex:sub(5, 6), 16) or 255)
end

local function toFont(name)
    local ok, f = pcall(function() return Enum.Font[name] end)
    if ok and f then return f end
    return Enum.Font.Gotham
end

--- Merge TAGDATA.defaults + the role preset + this player's own overrides into one plain table.
local function resolveTag(role, overrides, fallbackLabel)
    local out = {}
    for k, v in pairs(TAGDATA.defaults) do out[k] = v end
    local preset = TAGDATA.presets[role]
    if preset then for k, v in pairs(preset) do out[k] = v end end
    if overrides then for k, v in pairs(overrides) do out[k] = v end end
    if out.label == nil or out.label == "" then
        out.label = fallbackLabel or (TAGDATA.roles[role] and TAGDATA.roles[role].label) or "Member"
    end
    return out
end

local function glyphFor(role)
    local meta = TAGDATA.roles[role]
    return meta and meta.glyph or "🌙"
end

Nametags.TAGDATA = TAGDATA

-- ═══════════════════════════════════════════════════════════════════════════
--  EXPORT CODES   SCORPTAG1.<base64url(json)>.<adler32 hex>
--  The tag editor makes these; the Discord bot's /tag import reads them (same format,
--  implemented in src/tagconfig.js). The JSON only holds options that differ from the
--  defaults, keys sorted so the same design always gives the same code.
-- ═══════════════════════════════════════════════════════════════════════════
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64LOOKUP = {}
for i = 1, #B64 do B64LOOKUP[B64:sub(i, i)] = i - 1 end
B64LOOKUP["+"] = 62
B64LOOKUP["/"] = 63

local function b64encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
        if b then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) end
        if c then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) end
    end
    return table.concat(out)
end

local function b64decode(s)
    local out, n, count = {}, 0, 0
    for i = 1, #s do
        local v = B64LOOKUP[s:sub(i, i)]
        if v == nil then return nil end
        n = n * 64 + v
        count = count + 1
        if count == 4 then
            out[#out + 1] = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
            n, count = 0, 0
        end
    end
    if count == 1 then return nil end
    if count == 2 then
        out[#out + 1] = string.char(math.floor(n / 16) % 256)
    elseif count == 3 then
        out[#out + 1] = string.char(math.floor(n / 1024) % 256, math.floor(n / 4) % 256)
    end
    return table.concat(out)
end

local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function hex8(n)
    local digits = "0123456789abcdef"
    local out = {}
    for i = 8, 1, -1 do
        local d = n % 16
        out[i] = digits:sub(d + 1, d + 1)
        n = math.floor(n / 16)
    end
    return table.concat(out)
end

local function jsonString(s)
    local escaped = s:gsub('[%c"\\]', function(ch)
        if ch == '"' then return '\\"' end
        if ch == "\\" then return "\\\\" end
        return string.format("\\u%04x", ch:byte())
    end)
    return '"' .. escaped .. '"'
end

--- Flat { key = string|number|boolean } → JSON with sorted keys (deterministic).
local function encodeFlat(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        local body
        if type(v) == "string" then body = jsonString(v)
        elseif type(v) == "boolean" then body = v and "true" or "false"
        else body = string.format("%.10g", v) end
        parts[#parts + 1] = jsonString(k) .. ":" .. body
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local COLOR_SET, FONT_SET, ANIM_SET = {}, {}, {}
for _, k in ipairs(TAGDATA.colorKeys) do COLOR_SET[k] = true end
for _, f in ipairs(TAGDATA.fonts) do FONT_SET[f] = true end
for _, a in ipairs(TAGDATA.animations) do ANIM_SET[a] = true end

--- Keep only options this version knows, with the right type and a sane value.
--- (The server re-validates everything; this just keeps the editor from loading junk.)
local function cleanOverrides(data)
    local out = {}
    for k, v in pairs(data) do
        local dv = TAGDATA.defaults[k]
        if dv ~= nil and type(v) == type(dv) then
            local keep = true
            if COLOR_SET[k] then keep = type(v) == "string" and v:match("^#%x%x%x%x%x%x$") ~= nil
            elseif k == "rankFont" or k == "userFont" then keep = FONT_SET[v] == true
            elseif k == "textAnimation" then keep = ANIM_SET[v] == true
            elseif k == "image" or k == "background" then keep = v == "" or v:match("^rbxassetid://%d+$") ~= nil
            elseif k == "label" or k == "userText" then v = v:sub(1, 24)
            elseif type(v) == "number" then
                local r = TAGDATA.ranges[k]
                if r then v = math.max(r[1], math.min(r[2], v)) end
            end
            if keep then out[k] = v end
        end
    end
    return out
end

--- Options → "SCORPTAG1.…" code.
function Nametags.Export(overrides)
    local clean = {}
    for k, v in pairs(cleanOverrides(overrides or {})) do clean[k] = v end
    local json = encodeFlat(clean)
    return TAGDATA.codePrefix .. "." .. b64encode(json) .. "." .. hex8(adler32(json))
end

--- Code → options table, or nil + a readable reason.
function Nametags.Import(code)
    code = tostring(code or ""):gsub("[%s`\"']", "")
    local prefix, payload, sum = code:match("^(%w+)%.([%w%-_+/]+)%.(%x+)$")
    if prefix ~= TAGDATA.codePrefix or not payload then return nil, "that isn't a Scorp tag code" end
    local json = b64decode(payload)
    if not json then return nil, "the code is damaged — copy the whole thing again" end
    if hex8(adler32(json)) ~= sum:lower() then return nil, "checksum mismatch — copy the whole code again" end
    local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(data) ~= "table" then return nil, "the code's contents aren't readable" end
    return cleanOverrides(data)
end

function Nametags.Color(hex) return toColor3(hex) end

function Nametags.ColorToHex(c)
    local function h(v) return string.format("%02x", math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)) end
    return "#" .. h(c.R) .. h(c.G) .. h(c.B)
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
local roster = {}        -- [userId] = { userId, username, displayName, role, label, tag }
local tags = {}           -- [userId] = { gui, head, key, tween, ..., effective }
local thumbs = {}        -- [userId] = rbxthumb content string
local preview = nil      -- { role, label, tag } local-only override for your own tag
local holder = nil
local warnedBuild = {}

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

--- A few small floating dots inside the card, for T.particles.
local function addParticles(card, cardW, cardH, color)
    local rng = Random.new(tick() * 1000 % 100000)
    for i = 1, 5 do
        local p = make("Frame", {
            Name = "Particle", BackgroundColor3 = color, BorderSizePixel = 0,
            Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 0.4,
            Position = UDim2.fromOffset(rng:NextInteger(6, math.max(7, math.floor(cardW) - 6)), rng:NextInteger(6, math.max(7, math.floor(cardH) - 6))),
        }, card)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
        local tw = TweenService:Create(
            p, TweenInfo.new(rng:NextNumber(1.6, 3.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { Position = p.Position + UDim2.fromOffset(0, -6), BackgroundTransparency = 0.85 }
        )
        tw:Play()
    end
end

--- Faint horizontal grid lines, for T.grid.
local function addGrid(card, cardW, cardH, color)
    for i = 1, 2 do
        make("Frame", {
            Name = "GridLine", BackgroundColor3 = color, BorderSizePixel = 0,
            BackgroundTransparency = 0.9, Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.new(0, 0, 0, math.floor(cardH * i / 3)),
        }, card)
    end
end

--- Occasional flicker on the title label, for T.glitch.
local function addGlitch(titleLabel, color)
    task.spawn(function()
        while titleLabel.Parent do
            task.wait(math.random(25, 60) / 10)
            if not titleLabel.Parent then break end
            local orig = titleLabel.TextColor3
            titleLabel.TextColor3 = color
            titleLabel.Position = titleLabel.Position + UDim2.fromOffset(1, 0)
            task.wait(0.04)
            if not titleLabel.Parent then break end
            titleLabel.TextColor3 = orig
            titleLabel.Position = titleLabel.Position - UDim2.fromOffset(1, 0)
        end
    end)
end

--- Underline that sweeps left-to-right beneath the title, for T.underlineSweep.
local function addUnderlineSweep(card, x, y, w, colorA, colorB)
    local line = make("Frame", {
        Name = "Underline", BackgroundColor3 = WHITE, BorderSizePixel = 0,
        Size = UDim2.fromOffset(w, 1.5), Position = UDim2.fromOffset(x, y),
    }, card)
    local grad = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, colorA), ColorSequenceKeypoint.new(0.5, colorB), ColorSequenceKeypoint.new(1, colorA),
        }),
    }, line)
    TweenService:Create(grad, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) }):Play()
    return line
end

--- Text colour animation for the title label: shimmer / rainbow / wave. "default" does nothing extra.
local function applyTextAnimation(titleLabel, kind, baseColor)
    if kind == "shimmer" then
        local grad = make("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, baseColor), ColorSequenceKeypoint.new(0.45, baseColor),
                ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.55, baseColor),
                ColorSequenceKeypoint.new(1, baseColor),
            }),
        }, titleLabel)
        TweenService:Create(grad, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) }):Play()
    elseif kind == "rainbow" then
        local grad = make("UIGradient", { Color = ColorSequence.new(Color3.fromHSV(0, 1, 1), Color3.fromHSV(1, 1, 1)) })
        grad.Parent = titleLabel
        task.spawn(function()
            local t = 0
            while titleLabel.Parent do
                t = (t + 0.01) % 1
                grad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(t, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV((t + 0.4) % 1, 1, 1)),
                })
                task.wait(0.05)
            end
        end)
    elseif kind == "wave" then
        TweenService:Create(
            titleLabel, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { Position = titleLabel.Position + UDim2.fromOffset(0, 2) }
        ):Play()
    end
end

local function buildTag(userId, info, head, previewParent)
    local T = resolveTag(info.role, info.tag, info.label)
    local rankFont, userFont = toFont(T.rankFont), toFont(T.userFont)
    local accent, primary = toColor3(T.accentA), toColor3(T.primary)

    local title = tostring(T.label)
    local shownUser = T.userText
    local name = ""
    if shownUser == "auto" or shownUser == nil then
        name = tostring(info.displayName or info.username or "")
    elseif shownUser ~= "none" then
        name = tostring(shownUser)
    end

    local textW = math.max(textWidth(title, T.textSize, rankFont), name ~= "" and textWidth(name, 12, userFont) or 0)
    local badgeSize = T.miniSize > 0 and math.min(T.miniSize, T.fullHeight - 12) or 30
    local pad, gap = 10, 9
    local cardW = T.fullWidth > 0 and T.fullWidth or math.clamp(pad + badgeSize + gap + textW + pad + 4, 120, 300)
    local cardH = T.fullHeight
    local margin = 10 -- room around the card for the glow

    local gui
    if previewParent then
        -- 2-D copy of the same tag (the tag editor's live preview) instead of a BillboardGui over a head
        gui = make("Frame", {
            Name = "ScorpTagPreview",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(cardW + margin * 2, cardH + margin * 2),
            BackgroundTransparency = 1,
        })
    else
        gui = make("BillboardGui", {
            Name = "ScorpTag",
            Adornee = head,
            Size = UDim2.fromOffset(cardW + margin * 2, cardH + margin * 2),
            StudsOffset = Vector3.new(0, T.offsetFull, 0),
            AlwaysOnTop = S.AlwaysOnTop,
            MaxDistance = math.min(S.MaxDistance, T.distMax),
            LightInfluence = 0,
            Active = false,
        })
    end
    local scaleObj = make("UIScale", { Scale = 1 }, gui)

    -- soft outer glow (T.glow)
    local glowFrame = nil
    if T.glow then
        local glow = make("Frame", {
            Name = "Glow",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(cardW + 6, cardH + 6),
            BackgroundTransparency = 1,
        }, gui)
        glowFrame = glow
        make("UICorner", { CornerRadius = UDim.new(0, 16) }, glow)
        local glowStroke = make("UIStroke", { Thickness = 5, Color = toColor3(T.outerGlowColor), Transparency = 0.82 }, glow)
        if T.pulse then
            TweenService:Create(glowStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.55 }):Play()
        end
    end

    -- card
    local card = make("Frame", {
        Name = "Card",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(cardW, cardH),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, gui)
    local cardCorner = make("UICorner", { CornerRadius = UDim.new(0, 13) }, card)
    make("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(toColor3(T.backgroundColorA), toColor3(T.backgroundColorC)),
    }, card)
    if T.background ~= "" then
        make("ImageLabel", {
            Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Image = T.background, ImageColor3 = toColor3(T.backgroundImageColor), ScaleType = Enum.ScaleType.Crop, ZIndex = 0,
        }, card)
    end
    if T.pulse then
        TweenService:Create(card, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.18 }):Play()
    end
    if T.grid then addGrid(card, cardW, cardH, toColor3(T.gridColor)) end
    if T.particles then addParticles(card, cardW, cardH, toColor3(T.particleColorA)) end

    -- border with a light that travels around it (T.spin)
    local stroke = make("UIStroke", {
        Thickness = 2, Color = WHITE,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, card)
    local sweepColors = T.spin
        and ColorSequence.new({
            ColorSequenceKeypoint.new(0, toColor3(T.outlineColorA)), ColorSequenceKeypoint.new(0.42, toColor3(T.outlineColorA)),
            ColorSequenceKeypoint.new(0.5, toColor3(T.highlightColor)), ColorSequenceKeypoint.new(0.58, toColor3(T.outlineColorB)),
            ColorSequenceKeypoint.new(1, toColor3(T.outlineColorC)),
        })
        or ColorSequence.new(toColor3(T.outlineColorA))
    local sweep = make("UIGradient", { Color = sweepColors }, stroke)
    local tween = nil
    if T.spin then
        tween = TweenService:Create(sweep, TweenInfo.new(3.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
        tween:Play()
    end

    -- round emblem (role glyph / custom image, replaced by the player's headshot once it loads)
    local badge = make("Frame", {
        Name = "Badge",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, pad, 0.5, 0),
        Size = UDim2.fromOffset(badgeSize, badgeSize),
        BackgroundColor3 = toColor3(T.borderColor),
        BorderSizePixel = 0,
    }, card)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
    make("UIStroke", { Thickness = 1.5, Color = accent, Transparency = 0.1 }, badge)
    local glyph = make("TextLabel", {
        Name = "Glyph",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = glyphFor(info.role),
        TextSize = math.floor(badgeSize * 0.52),
        TextColor3 = primary,
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
    if T.image ~= "" then
        avatar.Image = T.image
        avatar.Visible = true
        glyph.Visible = false
    else
        loadAvatar(userId, avatar, glyph)
    end
    local logoTween = nil
    if T.logoMotion then
        logoTween = TweenService:Create(badge, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = badge.Position + UDim2.fromOffset(0, -3) })
        logoTween:Play()
    end

    -- text
    local textLeft = pad + badgeSize + gap
    local titleLabel = make("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(textLeft, 5),
        Size = UDim2.new(1, -(textLeft + pad), 0, 19),
        BackgroundTransparency = 1,
        Text = title,
        TextSize = T.textSize,
        Font = rankFont,
        TextColor3 = primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)
    make("UIStroke", {
        Thickness = 1, Color = toColor3(T.textStrokeColor), Transparency = 0.72,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
    }, titleLabel)
    if T.effects then applyTextAnimation(titleLabel, T.textAnimation, primary) end
    if T.effects and T.glitch then addGlitch(titleLabel, toColor3(T.glitchColor)) end

    local nameLabel = nil
    if name ~= "" then
        nameLabel = make("TextLabel", {
            Name = "Name",
            Position = UDim2.fromOffset(textLeft, 23),
            Size = UDim2.new(1, -(textLeft + pad), 0, 14),
            BackgroundTransparency = 1,
            Text = name,
            TextSize = 12,
            Font = userFont,
            TextColor3 = toColor3(T.nameColor),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
    end
    local underline = nil
    if T.effects and T.underlineSweep then
        underline = addUnderlineSweep(card, textLeft, 19, textW + 4, toColor3(T.underlineColorA), toColor3(T.underlineColorB))
    end

    gui.Parent = previewParent or getHolder()
    return gui, tween, {
        T = T, gui = gui, scale = scaleObj, card = card, corner = cardCorner, glow = glowFrame, badge = badge,
        title = titleLabel, nameLabel = nameLabel, underline = underline, logoTween = logoTween,
        cardW = cardW, cardH = cardH, badgeSize = badgeSize, pad = pad,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
--  DISTANCE LEVEL-OF-DETAIL  (distFull / distMini / distMax from the design)
--    ≤ distFull   full card
--    → distMini   full card, shrinking a little with distance
--    ≥ distMini   logo only (miniSize)
--    > distMax    hidden
--  If the camera position can't be read, tags simply stay full size.
-- ═══════════════════════════════════════════════════════════════════════════
local function distanceToCamera(head)
    local ok, d = pcall(function()
        local cam = workspace.CurrentCamera.CFrame.Position
        local p = head.Position
        local dx, dy, dz = p.X - cam.X, p.Y - cam.Y, p.Z - cam.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    if ok and type(d) == "number" then return d end
    return nil
end

local function updateLOD(t)
    local P = t.parts
    if not P then return end
    local T = P.T
    local d = distanceToCamera(t.head)
    local state, scale = "full", 1
    if d then
        if d > T.distMax then state = "hidden"
        elseif d >= T.distMini then state = "mini"
        elseif d > T.distFull then scale = 1 - 0.25 * (d - T.distFull) / math.max(1, T.distMini - T.distFull) end
    end
    if t.state == state and math.abs((t.scale or 1) - scale) < 0.02 then return end
    t.state, t.scale = state, scale
    P.gui.Enabled = state ~= "hidden"
    P.scale.Scale = scale
    local mini = state == "mini"
    local w, h = P.cardW, P.cardH
    if mini then w, h = T.miniSize, T.miniSize end
    P.card.Size = UDim2.fromOffset(w, h)
    P.corner.CornerRadius = mini and UDim.new(1, 0) or UDim.new(0, 13)
    if P.glow then P.glow.Size = UDim2.fromOffset(w + 6, h + 6) end
    P.title.Visible = not mini
    if P.nameLabel then P.nameLabel.Visible = not mini end
    if P.underline then P.underline.Visible = not mini end
    if mini then
        P.badge.AnchorPoint = Vector2.new(0.5, 0.5)
        P.badge.Position = UDim2.new(0.5, 0, 0.5, 0)
        P.badge.Size = UDim2.fromOffset(math.max(12, T.miniSize - 8), math.max(12, T.miniSize - 8))
        if P.logoTween then pcall(function() P.logoTween:Cancel() end) end
    else
        P.badge.AnchorPoint = Vector2.new(0, 0.5)
        P.badge.Position = UDim2.new(0, P.pad, 0.5, 0)
        P.badge.Size = UDim2.fromOffset(P.badgeSize, P.badgeSize)
        if P.logoTween then pcall(function() P.logoTween:Play() end) end
    end
    P.gui.StudsOffset = Vector3.new(0, mini and T.offsetMini or T.offsetFull, 0)
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
    local overrides = info.tag
    local sig = ""
    if overrides then
        local ok, encoded = pcall(function() return HttpService:JSONEncode(overrides) end)
        sig = ok and encoded or tostring(overrides)
    end
    return tostring(info.role) .. "|" .. tostring(info.label) .. "|" .. tostring(info.displayName) .. "|" .. sig
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
            tag = preview.tag,
        }
    end
    return roster[userId]
end

local function applyTag(userId)
    local info = infoFor(userId)
    local player = Players:GetPlayerByUserId(userId)
    if not info or not player or not S.Enabled then return removeTag(userId) end
    if userId == LocalPlayer.UserId and not S.ShowSelf then return removeTag(userId) end
    if info.role == "member" and not S.ShowMembers and not info.tag then return removeTag(userId) end

    local head = getHead(player)
    if not head then return removeTag(userId) end

    local key = tagKey(info)
    local t = tags[userId]
    if t and t.head == head and t.key == key and t.gui.Parent then
        t.gui.MaxDistance = math.min(S.MaxDistance, t.parts and t.parts.T.distMax or S.MaxDistance)
        t.gui.AlwaysOnTop = S.AlwaysOnTop
        return
    end

    removeTag(userId)
    local ok, gui, tween, parts = pcall(buildTag, userId, info, head)
    if ok and gui then
        tags[userId] = { gui = gui, head = head, key = key, tween = tween, parts = parts }
        updateLOD(tags[userId])
    elseif not ok and not warnedBuild[key] then
        warnedBuild[key] = true   -- once per distinct design, so a bad option can't spam the console
        warn("[Scorp] couldn't draw a nametag: " .. tostring(gui))
    end
end

local function render()
    for userId in pairs(tags) do
        if not infoFor(userId) then removeTag(userId) end
    end
    for userId in pairs(roster) do applyTag(userId) end
    if preview then applyTag(LocalPlayer.UserId) end
    for _, t in pairs(tags) do updateLOD(t) end
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
    if role and TAGDATA.presets[role] then
        preview = { role = role, label = label or (TAGDATA.roles[role] and TAGDATA.roles[role].label) }
    else
        preview = nil
        removeTag(LocalPlayer.UserId)
    end
    render()
end

--- Show a draft design (options table) on your own tag in the world. Nametags.PreviewTag(nil) turns it off.
function Nametags.PreviewTag(overrides)
    if overrides then
        preview = { role = "member", tag = overrides }
    else
        preview = nil
        removeTag(LocalPlayer.UserId)
    end
    render()
end

--- Draw a 2-D copy of a design inside any GuiObject (the editor's live preview).
--- Returns the frame and the border tween (cancel it when you destroy the frame), or nil if it couldn't draw.
function Nametags.PreviewCard(parent, overrides, role)
    local info = {
        userId = LocalPlayer.UserId,
        username = LocalPlayer.Name,
        displayName = LocalPlayer.DisplayName,
        role = role or "member",
        tag = overrides,
    }
    local ok, gui, tween = pcall(buildTag, LocalPlayer.UserId, info, nil, parent)
    if ok and gui then return gui, tween end
    warn("[Scorp] couldn't draw the tag preview: " .. tostring(gui))
    return nil
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
