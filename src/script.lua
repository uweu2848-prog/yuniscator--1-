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

-- Yuniku-inspired local shader and post-processing engine.
local Shaders = (function()
--@include shaders.lua
end)()

-- Read-only current-server roster and client-local playlist.
local PlayerRoster = (function()
--@include playerroster.lua
end)()

local Playlist = (function()
--@include playlist.lua
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
    Subtitle     = "IDENTITY  ·  VISUALS  ·  COMMUNITY",
    Theme        = "Aurora Glass",
    Size         = UDim2.fromOffset(1000, 660),
    MinSize      = Vector2.new(820, 540),
    MaxSize      = Vector2.new(1320, 900),
    ToggleKey    = Enum.KeyCode.RightShift,
    UnloadKey    = Enum.KeyCode.Delete,
    WidgetText   = "SCORP",
    ConfigFolder = "Scorp",
    Starfield    = true,
    StarCount    = 38,
    Nebula       = true,
    BlurSize     = 8,
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

local StaffPanel = staffAuthorized and AdminPanel and AdminPanel.Build(Window, ctx) or nil
local TagManagerPanel = (tagManagerAuthorized and not staffAuthorized and TagPanel) and TagPanel.Build(Window, ctx) or nil
local SupportStaffPanel = (supportAuthorized and not staffAuthorized and not tagManagerAuthorized and SupportPanel) and SupportPanel.Build(Window, ctx) or nil
local Editor = nil
local ShaderEngine = nil
local Roster = nil
local PlaylistPlayer = nil

-- ───────────────────────────────────────────────────────────────────────────
--  Home
-- ───────────────────────────────────────────────────────────────────────────
local Home = Window:CreateTab("Home", { Icon = "✦", Group = "Workspace" })

do
    local hero = Home:CreateSection("SCORP SPACE", true)
    local card = hero:AddCustom(142)
    card.BackgroundColor3 = Window.Theme.ToggleOff
    card.BackgroundTransparency = 0.12
    card.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = card
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Transparency = 0.22
    stroke.Color = Window.Theme.AccentLight
    stroke.Parent = card
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 16
    gradient.Color = ColorSequence.new(Window.Theme.Accent, Window.Theme.AccentLight)
    gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 0.97) })
    gradient.Parent = card

    local eyebrow = Instance.new("TextLabel")
    eyebrow.BackgroundTransparency = 1
    eyebrow.Position = UDim2.fromOffset(20, 15)
    eyebrow.Size = UDim2.new(1, -40, 0, 18)
    eyebrow.Font = Enum.Font.GothamBold
    eyebrow.Text = "✦   YOUR COMMUNITY CLIENT"
    eyebrow.TextColor3 = Window.Theme.AccentLight
    eyebrow.TextSize = 11
    eyebrow.TextXAlignment = Enum.TextXAlignment.Left
    eyebrow.Parent = card

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(18, 38)
    title.Size = UDim2.new(1, -36, 0, 37)
    title.Font = Enum.Font.GothamBlack
    title.Text = "MAKE SCORP YOURS"
    title.TextColor3 = Window.Theme.TextWhite
    title.TextSize = 25
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local description = Instance.new("TextLabel")
    description.BackgroundTransparency = 1
    description.Position = UDim2.fromOffset(20, 80)
    description.Size = UDim2.new(1, -40, 0, 42)
    description.Font = Enum.Font.Gotham
    description.Text = "Personalize your identity, tune your visuals, and explore the Scorp community."
    description.TextColor3 = Window.Theme.TextDim
    description.TextSize = 13
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.Parent = card

    Window:_bind(function(theme)
        card.BackgroundColor3 = theme.ToggleOff
        stroke.Color = theme.AccentLight
        gradient.Color = ColorSequence.new(theme.Accent, theme.AccentLight)
        eyebrow.TextColor3 = theme.AccentLight
        title.TextColor3 = theme.TextWhite
        description.TextColor3 = theme.TextDim
    end)
end

do
    local sec = Home:CreateSection("QUICK ACCESS", true)
    sec:AddLabel("Jump straight into your most-used Scorp tools.", { Wrap = true, Color = Window.Theme.TextDim })
    sec:AddButton("🏷️   Open Name Tag Studio", function()
        if Editor then Editor.Open() end
    end)
    sec:AddButton("✨   Open Shader Studio", function()
        if ShaderEngine then ShaderEngine.Open() end
    end)
    sec:AddButton("♫   Open Playlist", function()
        if PlaylistPlayer then PlaylistPlayer.Open() end
    end)
    sec:AddButton("♙   Open Player List", function()
        if Roster then Roster.Open() end
    end)
    sec:AddButton("♫   Open Playlist", function()
        if PlaylistPlayer then PlaylistPlayer.Open() end
    end)
    if StaffPanel then
        sec:AddButton("⚑   Open Staff Console", function() StaffPanel.Open() end)
    elseif TagManagerPanel then
        sec:AddButton("✦   Open Tag Studio · Staff", function() TagManagerPanel.Open() end)
    elseif SupportStaffPanel then
        sec:AddButton("◈   Open Support Desk", function() SupportStaffPanel.Open() end)
    end
end

do
    local sec = Home:CreateSection("SESSION OVERVIEW", false)
    local summary = sec:AddLabel("SCORP ONLINE\nLoading client details…", { Wrap = true, TextSize = 12, Color = Window.Theme.TextWhite })
    local function refreshSummary()
        local place = tostring(game.PlaceId or "Unknown")
        local playerCount = #Players:GetPlayers()
        summary:Set(("SCORP ONLINE  ·  %s\nWelcome, %s  ·  %d players in this server\nPlace ID  %s  ·  Build  %s"):format(
            tostring(ctx.releaseChannel or "production"):upper(), tostring(LocalPlayer.DisplayName or LocalPlayer.Name),
            playerCount, place, tostring(ctx.releaseVersion or ctx.build or "local")))
    end
    refreshSummary()
    Window:_connect(Players.PlayerAdded, refreshSummary)
    Window:_connect(Players.PlayerRemoving, function() task.defer(refreshSummary) end)
    sec:AddButton("↻   Refresh Session Overview", refreshSummary)
end

-- Keep navigation focused on real, supported features rather than demo tabs.
Roster = PlayerRoster.Build(Window, Players, LocalPlayer)
Editor = TagEditor.Build(Window, Nametags)
ShaderEngine = Shaders.Build(Window)
PlaylistPlayer = Playlist.Build(Window)

do
    local About = Window:CreateTab("About", { Icon = "ⓘ", Group = "About" })
    local section = About:CreateSection("ABOUT SCORP", true)
    section:AddLabel("SCORP · Identity / Visuals / Community", { Wrap = true, TextSize = 15, Color = Window.Theme.AccentLight })
    section:AddLabel("A community client for player identity, local visual customization, and server-aware nametags.", { Wrap = true, Color = Window.Theme.TextWhite })
    section:AddLabel("Release  " .. tostring(ctx.releaseChannel or "production") .. " · " .. tostring(ctx.releaseVersion or ctx.build or "unversioned"), { Wrap = true, Color = Window.Theme.TextDim })
    section:AddButton("Copy Scorp Discord Invite", function()
        local invite = "https://discord.gg/scorp"
        local copy = setclipboard or toclipboard
        if type(copy) == "function" and pcall(copy, invite) then
            Window:Notify("Invite copied", "Discord invite copied to clipboard.", 3, Window.Theme.Success)
        else
            Window:Notify("Scorp Community", invite, 5, Window.Theme.AccentLight)
        end
    end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Settings
-- ───────────────────────────────────────────────────────────────────────────
local Settings = Window:CreateTab("Settings", { Icon = "⚙️", Group = "Preferences" })

Window:AddThemeControls(Settings, "01 · Appearance")
Window:AddConfigControls(Settings, "02 · Configurations")

do
    local sec = Settings:CreateSection("03 · Controls", true)
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
    local sec = Settings:CreateSection("04 · Nametag Display", true)
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

local InfoBar = Window:CreateInfoBar({
    Brand = "SCORP",
    Channel = tostring(ctx.releaseChannel or "production"):upper(),
    OnSettings = function()
        Window:Toggle(true)
        Window:SelectTab(Settings)
    end,
    OnGlobe = function()
        if ShaderEngine then ShaderEngine.Open() end
    end,
    OnNametag = function()
        if Editor then Editor.Open() end
    end,
    OnPlaylist = function()
        if PlaylistPlayer then PlaylistPlayer.Open() end
    end,
    OnDiscord = function()
        local invite = "https://discord.gg/scorp"
        local copy = setclipboard or toclipboard
        if type(copy) == "function" and pcall(copy, invite) then
            Window:Notify("Community Invite", "Discord invite copied to clipboard.", 3, Window.Theme.Success)
        else
            Window:Notify("Community Invite", invite, 5, Window.Theme.AccentLight)
        end
    end,
})

-- ───────────────────────────────────────────────────────────────────────────
--  Session hooks + cleanup
-- ───────────────────────────────────────────────────────────────────────────
-- The loader calls this if the server revokes the session mid-run.
ctx.revoke = function(message, updateRequired)
    local reason = tostring(message or (updateRequired and "Scorp was updated. Relaunch the latest loader to continue." or "Your Scorp session was revoked."))
    if updateRequired then
        pcall(Editor.Destroy)
        pcall(ShaderEngine.Destroy)
        pcall(PlaylistPlayer.Destroy)
        pcall(Roster.Destroy)
        pcall(InfoBar.Destroy)
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
    pcall(ShaderEngine.Destroy)
    pcall(PlaylistPlayer.Destroy)
    pcall(Roster.Destroy)
    pcall(InfoBar.Destroy)
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
