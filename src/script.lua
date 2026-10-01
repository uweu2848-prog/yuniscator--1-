-- ───────────────────────────────────────────────────────────────────────────
--  Scorp payload  (src/script.lua → obfuscated to dist/script.lua by the build)
--
--  This is NOT run directly. loader.lua downloads the built version from your
--  server and calls it with a context table:
--      ctx.token       session token (renewed automatically by the loader)
--      ctx.server      your backend URL
--      ctx.request     the executor's HTTP request function
--      ctx.loadstring  loadstring, captured before anything could hook it
--      ctx.lib         source of the UI library (served by the server, not GitHub)
--      ctx.revoke      set below — the loader calls it if the server revokes you
-- ───────────────────────────────────────────────────────────────────────────
local ctx = ...
if type(ctx) ~= "table" or not ctx.token or not ctx.lib then
    warn("[Scorp] start this with the loader, not directly.")
    return
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Nametag system (design + sync live in src/nametags.lua; the build inlines it here)
local Nametags = (function()
--@include nametags.lua
end)()

-- Free name-tag presets + preview live in src/tageditor.lua.
local TagEditor = (function()
--@include tageditor.lua
end)()

-- Staff-panel code is fetched separately only after the server authorizes this session.
local AdminPanel = nil
local TagPanel = nil
local SupportPanel = nil

-- ───────────────────────────────────────────────────────────────────────────
--  UI library (delivered by the server over the authenticated session)
-- ───────────────────────────────────────────────────────────────────────────
local libFn, libErr = ctx.loadstring(ctx.lib)
assert(libFn, "[Scorp] UI library failed to compile: " .. tostring(libErr))
local Scorp = libFn()
assert(Scorp, "[Scorp] UI library ran but returned nothing.")
ctx.lib = nil -- don't keep the library source sitting in the shared table

-- ───────────────────────────────────────────────────────────────────────────
--  Window
-- ───────────────────────────────────────────────────────────────────────────
local Window = Scorp:CreateWindow({
    Title        = "SCORP",
    Subtitle     = "Community · Identity · Experience",
    Theme        = "Cosmic Void",
    Size         = UDim2.fromOffset(940, 610),
    MinSize      = Vector2.new(760, 500),
    MaxSize      = Vector2.new(1240, 820),
    ToggleKey    = Enum.KeyCode.RightShift,
    UnloadKey    = Enum.KeyCode.Delete,
    WidgetText   = "✦",
    ConfigFolder = "Scorp",
    Starfield    = true,
    StarCount    = 42,
    Nebula       = true,
    BlurSize     = 12,
})
assert(type(Window) == "table" and type(Window.CreateTab) == "function",
    "[Scorp] incompatible UI library: Window:CreateTab is missing. Deploy/restart the server with src/ScorpLib.lua.")

-- Ask the authenticated server whether this session is a configured staff ID.
-- Do not construct or attach any staff UI when the answer is missing/negative.
local staffAuthorized = false
local tagManagerAuthorized = false
local supportAuthorized = false
do
    local ok, response = pcall(ctx.request, {
        Url = ctx.server .. "/api/panel/authorize",
        Method = "GET",
        Headers = { ["Authorization"] = "Bearer " .. tostring(ctx.token) },
    })
    if ok and type(response) == "table" and response.StatusCode == 200 then
        local decoded, data = pcall(function()
            return game:GetService("HttpService"):JSONDecode(response.Body or "")
        end)
        staffAuthorized = decoded and type(data) == "table" and data.authorized == true
        tagManagerAuthorized = decoded and type(data) == "table" and data.tagManager == true
        supportAuthorized = decoded and type(data) == "table" and data.support == true
    end
    if staffAuthorized then
        local moduleOk, moduleResponse = pcall(ctx.request, {
            Url = ctx.server .. "/api/panel/module",
            Method = "GET",
            Headers = { ["Authorization"] = "Bearer " .. tostring(ctx.token) },
        })
        if moduleOk and type(moduleResponse) == "table" and moduleResponse.StatusCode == 200 and type(moduleResponse.Body) == "string" then
            local moduleFn, moduleErr = ctx.loadstring(moduleResponse.Body)
            if moduleFn then
                local loadedOk, module = pcall(moduleFn)
                if loadedOk and type(module) == "table" and type(module.Build) == "function" then
                    AdminPanel = module
                else
                    warn("[Scorp] authorized admin module failed to initialize: " .. tostring(module))
                end
            else
                warn("[Scorp] authorized admin module failed to compile: " .. tostring(moduleErr))
            end
        else
            warn("[Scorp] authorized admin module could not be fetched.")
        end
    elseif tagManagerAuthorized then
        local moduleOk, moduleResponse = pcall(ctx.request, {
            Url = ctx.server .. "/api/tag-panel/module",
            Method = "GET",
            Headers = { ["Authorization"] = "Bearer " .. tostring(ctx.token) },
        })
        if moduleOk and type(moduleResponse) == "table" and moduleResponse.StatusCode == 200 and type(moduleResponse.Body) == "string" then
            local moduleFn, moduleErr = ctx.loadstring(moduleResponse.Body)
            if moduleFn then
                local loadedOk, module = pcall(moduleFn)
                if loadedOk and type(module) == "table" and type(module.Build) == "function" then
                    TagPanel = module
                else
                    warn("[Scorp] authorized tag panel failed to initialize: " .. tostring(module))
                end
            else
                warn("[Scorp] authorized tag panel failed to compile: " .. tostring(moduleErr))
            end
        else
            warn("[Scorp] authorized tag panel could not be fetched.")
        end
    elseif supportAuthorized then
        local moduleOk, moduleResponse = pcall(ctx.request, {
            Url = ctx.server .. "/api/support-panel/module",
            Method = "GET",
            Headers = { ["Authorization"] = "Bearer " .. tostring(ctx.token) },
        })
        if moduleOk and type(moduleResponse) == "table" and moduleResponse.StatusCode == 200 and type(moduleResponse.Body) == "string" then
            local moduleFn, moduleErr = ctx.loadstring(moduleResponse.Body)
            if moduleFn then
                local loadedOk, module = pcall(moduleFn)
                if loadedOk and type(module) == "table" and type(module.Build) == "function" then
                    SupportPanel = module
                else
                    warn("[Scorp] authorized support panel failed to initialize: " .. tostring(module))
                end
            else
                warn("[Scorp] authorized support panel failed to compile: " .. tostring(moduleErr))
            end
        else
            warn("[Scorp] authorized support panel could not be fetched.")
        end
    end
end

Window:SetWatermark(('<font color="rgb(168,186,214)">Scorp</font>  ·  %s %s'):format(
    tostring(ctx.releaseChannel or "production"), tostring(ctx.releaseVersion or ctx.build or "unversioned")))

-- Build only real tools into the navigation. The former Player, Visuals and
-- Misc tabs were demo placeholders with callbacks that did nothing.
local Editor = TagEditor.Build(Window, Nametags)
local StaffPanel = staffAuthorized and AdminPanel and AdminPanel.Build(Window, ctx) or nil
local TagManagerPanel = (tagManagerAuthorized and not staffAuthorized and TagPanel) and TagPanel.Build(Window, ctx) or nil
local SupportStaffPanel = (supportAuthorized and not staffAuthorized and not tagManagerAuthorized and SupportPanel) and SupportPanel.Build(Window, ctx) or nil

-- ───────────────────────────────────────────────────────────────────────────
-- Overview dashboard
-- ───────────────────────────────────────────────────────────────────────────
local Home = Window:CreateTab("Overview", { Icon = "✦" })

do
    local hero = Home:CreateSection("YOUR SCORP SPACE", true)
    local card = hero:AddCustom(142)
    card.BackgroundColor3 = Window.Theme.ToggleOff
    card.BackgroundTransparency = 0.12
    card.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = card
    local border = Instance.new("UIStroke")
    border.Thickness = 1.5
    border.Transparency = 0.2
    border.Color = Window.Theme.AccentLight
    border.Parent = card
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 18
    gradient.Color = ColorSequence.new(Window.Theme.Accent, Window.Theme.AccentLight)
    gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.98) })
    gradient.Parent = card

    local kicker = Instance.new("TextLabel")
    kicker.BackgroundTransparency = 1
    kicker.Position = UDim2.new(0, 20, 0, 16)
    kicker.Size = UDim2.new(1, -40, 0, 18)
    kicker.Font = Enum.Font.GothamBold
    kicker.Text = "✦   SCORP COMMUNITY EXPERIENCE"
    kicker.TextColor3 = Window.Theme.AccentLight
    kicker.TextSize = 11
    kicker.TextXAlignment = Enum.TextXAlignment.Left
    kicker.Parent = card

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 18, 0, 39)
    title.Size = UDim2.new(1, -36, 0, 38)
    title.Font = Enum.Font.GothamBlack
    title.Text = "MAKE YOUR NAME STAND OUT"
    title.TextColor3 = Window.Theme.TextWhite
    title.TextSize = 24
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Parent = card

    local subtitle = Instance.new("TextLabel")
    subtitle.BackgroundTransparency = 1
    subtitle.Position = UDim2.new(0, 20, 0, 80)
    subtitle.Size = UDim2.new(1, -40, 0, 34)
    subtitle.Font = Enum.Font.Montserrat
    subtitle.Text = "Personalize your nametag, explore the community, and make Scorp yours."
    subtitle.TextColor3 = Window.Theme.TextDim
    subtitle.TextSize = 13
    subtitle.TextWrapped = true
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = card

    Window:_bind(function(theme)
        card.BackgroundColor3 = theme.ToggleOff
        border.Color = theme.AccentLight
        gradient.Color = ColorSequence.new(theme.Accent, theme.AccentLight)
        kicker.TextColor3 = theme.AccentLight
        title.TextColor3 = theme.TextWhite
        subtitle.TextColor3 = theme.TextDim
    end)
end

do
    local sec = Home:CreateSection("AT A GLANCE", true)
    local state = sec:AddLabel("SCORP ONLINE   ·   " .. tostring(ctx.releaseChannel or "production"):upper() .. " RELEASE\nWelcome, " .. tostring(LocalPlayer.DisplayName or LocalPlayer.Name) .. "   ·   " .. tostring(#Players:GetPlayers()) .. " players in this server", {
        Wrap = true, TextSize = 13, Color = Window.Theme.TextWhite,
    })
    local function refreshStatus()
        local characterState = LocalPlayer.Character and "Character ready" or "Waiting for character"
        state:Set("●  SCORP ONLINE   ·   " .. tostring(ctx.releaseChannel or "production"):upper()
            .. " RELEASE\nWelcome, " .. tostring(LocalPlayer.DisplayName or LocalPlayer.Name)
            .. "   ·   " .. tostring(#Players:GetPlayers()) .. " players here   ·   " .. characterState)
        Window:Notify("Overview refreshed", "Your Scorp client is ready.", 3, Window.Theme.Success)
    end
    sec:AddButton("Refresh Overview", refreshStatus)
end

do
    local sec = Home:CreateSection("QUICK LAUNCH", true)
    sec:AddLabel("Jump straight to the tools you actually use.", { Wrap = true, Color = Window.Theme.TextDim })
    sec:AddButton("✦  Open Name Tag Studio", function() Editor.Open() end)
    sec:AddButton("↻  Refresh Nearby Nametags", function()
        Nametags.Refresh()
        Window:Notify("Nametags", "Refreshing players in this server…", 3, Window.Theme.AccentLight)
    end)
    sec:AddButton("◉  Preview VIP Nametag", function()
        Nametags.Preview("vip")
        Window:Notify("Preview enabled", "Your personal tag is now showing the VIP style preview.", 4)
    end)
    sec:AddButton("×  Clear Nametag Preview", function()
        Nametags.Preview(nil)
        Window:Notify("Preview cleared", "Your normal nametag style is restored.", 3)
    end)
    if StaffPanel then
        sec:AddButton("⚑  Open Staff Console", function() StaffPanel.Open() end)
    elseif TagManagerPanel then
        sec:AddButton("✦  Open Tag Studio · Staff", function() TagManagerPanel.Open() end)
    elseif SupportStaffPanel then
        sec:AddButton("?  Open Support Desk", function() SupportStaffPanel.Open() end)
    end
end

do
    local sec = Home:CreateSection("NAVIGATION", false)
    sec:AddLabel("NAME TAGS\nDesign your colors, fonts, and effects in the Name Tags tab. Your Roblox username stays visible to the community.", { Wrap = true })
    sec:AddLabel("PERSONALIZE\nOpen Settings to adjust the interface theme, save a config, and control how nametags appear.", { Wrap = true, Color = Window.Theme.TextDim })
    sec:AddLabel("SHORTCUTS\nRightShift toggles this menu   ·   Delete unloads Scorp", { Wrap = true, Color = Window.Theme.AccentLight })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Settings
-- ───────────────────────────────────────────────────────────────────────────
local Settings = Window:CreateTab("Settings", { Icon = "⚙️" })

Window:AddThemeControls(Settings, "🎨 Theme")
Window:AddConfigControls(Settings, "💾 Configs")

do
    local sec = Settings:CreateSection("Menu", true)
    local menuToggle = sec:AddKeybind("Menu Toggle Key", {
        Default  = Window.ToggleKey,
        Flag = "menu_toggle_key",
        OnChange = function(key)
            Window:SetToggleKey(key)
            if not Window._loadingConfig then pcall(function() Window:SaveConfig("default") end) end
        end,
    })
    -- Config loading can only restore registered flags, so register first, then
    -- automatically restore the user's last saved default config if one exists.
    Window:_updateHint()
    local loaded = Window:LoadConfig("default")
    if loaded then Window:SetToggleKey(Window.Flags.menu_toggle_key or nil) end
end

-- ───────────────────────────────────────────────────────────────────────────
--  Nametag settings
-- ───────────────────────────────────────────────────────────────────────────
do
    local sec = Settings:CreateSection("Nametag Display", true)
    sec:AddToggle("Show Nametags", { Default = true, Bindable = false, Flag = "tags_on",
        Callback = function(v) Nametags.Set("Enabled", v) end })
    sec:AddToggle("Show My Own Tag", { Default = true, Bindable = false, Flag = "tags_self",
        Callback = function(v) Nametags.Set("ShowSelf", v) end })
    sec:AddToggle("Show Member Tags", { Default = true, Bindable = false, Flag = "tags_members",
        Callback = function(v) Nametags.Set("ShowMembers", v) end })
    sec:AddToggle("Player Avatars", { Default = true, Bindable = false, Flag = "tags_avatars",
        Callback = function(v) Nametags.Set("Avatars", v) end })
    sec:AddToggle("Visible Through Walls", { Default = true, Bindable = false, Flag = "tags_top",
        Callback = function(v) Nametags.Set("AlwaysOnTop", v) end })
    sec:AddSlider("Tag Distance", { Min = 30, Max = 400, Default = 150, Increment = 10, Suffix = " studs",
        Flag = "tags_dist", Callback = function(v) Nametags.Set("MaxDistance", v) end })
    sec:AddDropdown("Preview Style:", {
        Options = { "Off", "owner", "developer", "admin", "moderator", "support", "vip", "member" },
        Default = "Off",
        Callback = function(v)
            if v == "Off" then Nametags.Preview(nil) else Nametags.Preview(v) end
        end,
    })
    sec:AddButton("Refresh Nametags", function()
        Nametags.Refresh()
        Window:Notify("Nametags", "Refreshing…", 2)
    end)
    if StaffPanel then
        sec:AddButton("Open Admin Panel · Staff", function() StaffPanel.Open() end)
    elseif TagManagerPanel then
        sec:AddButton("Open Tag Manager · Staff", function() TagManagerPanel.Open() end)
    elseif SupportStaffPanel then
        sec:AddButton("Open Support Desk · Staff", function() SupportStaffPanel.Open() end)
    end
end

-- ───────────────────────────────────────────────────────────────────────────
--  Session hooks + cleanup
-- ───────────────────────────────────────────────────────────────────────────
-- The loader calls this if the server revokes the session mid-run.
ctx.revoke = function(message, updateRequired)
    local reason = tostring(message or (updateRequired and "Scorp was updated. Relaunch the latest loader to continue." or "Your Scorp session was revoked."))
    if updateRequired then
        pcall(Editor.Destroy)
        if StaffPanel then pcall(StaffPanel.Destroy) end
        if TagManagerPanel then pcall(TagManagerPanel.Destroy) end
        if SupportStaffPanel then pcall(SupportStaffPanel.Destroy) end
        pcall(Nametags.Stop)
        pcall(function() Window:Toggle(true) end)
        pcall(function() Window:Notify("Update Required", reason, 30, Window.Theme.Warning) end)
        task.delay(30.5, function() pcall(function() Window:Destroy(true) end) end)
        return
    end

    local overlay = Instance.new("ScreenGui")
    overlay.Name = "ScorpRevokedNotice"
    overlay.ResetOnSpawn = false
    overlay.IgnoreGuiInset = true
    overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlay.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.fromScale(0.42, 0.18)
    panel.BackgroundColor3 = Color3.fromRGB(20, 12, 16)
    panel.BorderSizePixel = 0
    panel.Parent = overlay

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(210, 62, 89)
    stroke.Transparency = 0.2
    stroke.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -32, 0, 28)
    title.Position = UDim2.new(0, 16, 0, 16)
    title.BackgroundTransparency = 1
    title.Text = "Scorp access revoked"
    title.TextColor3 = Color3.fromRGB(255, 240, 246)
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local body = Instance.new("TextLabel")
    body.Name = "Body"
    body.Size = UDim2.new(1, -32, 0, 58)
    body.Position = UDim2.new(0, 16, 0, 52)
    body.BackgroundTransparency = 1
    body.Text = reason
    body.TextColor3 = Color3.fromRGB(220, 210, 214)
    body.TextSize = 14
    body.Font = Enum.Font.Gotham
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Parent = panel

    pcall(function() Window:Notify("Access Revoked", reason, 10, Window.Theme.Danger) end)
    task.delay(8, function() if overlay and overlay.Parent then overlay:Destroy() end end)
    task.delay(0.3, function() pcall(function() Window:Destroy(true) end) end)
end

Window:OnUnload(function()
    print("[Scorp] unloaded")
    pcall(Editor.Destroy)
    if StaffPanel then pcall(StaffPanel.Destroy) end
    if TagManagerPanel then pcall(TagManagerPanel.Destroy) end
    if SupportStaffPanel then pcall(SupportStaffPanel.Destroy) end
    Nametags.Stop()
end)

Nametags.Start({
    ctx = ctx,
    request = ctx.request,
    server = ctx.server,
    onRevoked = function() ctx.revoke() end,
    notify = function(title, desc, duration) Window:Notify(title, desc, duration) end,
})
-- ── Floating HUD pill — always visible, lets user reopen the menu without a keybind ──
local _windowVisible = true   -- track Window open/close state for the pill label

Nametags.CreateHudButton(
    -- onEdit: open the standalone nametag editor window
    function()
        Editor.Open()
    end,

    -- onToggleScript: show/hide the main Scorp window; MUST return new visible state
    function()
        _windowVisible = not _windowVisible
        if _windowVisible then
            Window:Toggle(true)   -- force open
        else
            Window:Toggle(false)  -- force close
        end
        return _windowVisible
    end
)

Window:Notify("Scorp", "Loaded. Press " .. Window.ToggleKey.Name .. " to toggle.", 4)
