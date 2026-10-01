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

local function stub(name)
    return function(value)
        print(("[Scorp] %s -> %s"):format(name, tostring(value)))
    end
end

-- ───────────────────────────────────────────────────────────────────────────
--  Window
-- ───────────────────────────────────────────────────────────────────────────
local Window = Scorp:CreateWindow({
    Title        = "Scorp",
    Subtitle     = "A Out Of Space Experience  ·  v0.1",
    Theme        = "Sharp Silver",
    ToggleKey    = Enum.KeyCode.RightShift,
    UnloadKey    = Enum.KeyCode.Delete,
    WidgetText   = "Scorp",
    ConfigFolder = "Scorp",
    Starfield    = false,
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

-- ───────────────────────────────────────────────────────────────────────────
--  Home
-- ───────────────────────────────────────────────────────────────────────────
local Home = Window:CreateTab("Home", { Icon = "🏄" })

do
    local sec = Home:CreateSection("Welcome", true)
    sec:AddLabel("Scorp is running. Everything here is a placeholder.", { Wrap = true })
    sec:AddLabel("Made by YOUR_NAME", { Color = Window.Theme.TextDim })
    sec:AddButton("Test Notification", function()
        Window:Notify("Scorp", "Notifications are working.", 3)
    end)
    sec:AddButton("Success Notification", function()
        Window:Notify("Done", "This one uses the success colour.", 3, Window.Theme.Success)
    end)
end

do
    local sec = Home:CreateSection("Cosmic Core", true)
    sec:AddToggle("Placeholder Feature 1", { Flag = "core_1", Callback = stub("Placeholder Feature 1") })
    sec:AddToggle("Placeholder Feature 2", { Bindable = false, Flag = "core_2", Callback = stub("Placeholder Feature 2") })
    sec:AddToggle("Placeholder Feature 3", { Bindable = false, Flag = "core_3", Callback = stub("Placeholder Feature 3") })
    sec:AddSlider("Power Level", {
        Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
        Flag = "core_power", Callback = stub("Power Level"),
    })
    sec:AddDropdown("Mode:", {
        Options = { "Mode A", "Mode B", "Mode C" }, Default = "Mode A",
        Flag = "core_mode", Callback = stub("Mode"),
    })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Player
-- ───────────────────────────────────────────────────────────────────────────
local Player = Window:CreateTab("Player", { Icon = "🌠" })

do
    local sec = Player:CreateSection("Movement", true)
    sec:AddToggle("Movement Toggle 1", { Bindable = false, Flag = "move_1", Callback = stub("Movement Toggle 1") })
    sec:AddToggle("Movement Toggle 2", { Bindable = false, Flag = "move_2", Callback = stub("Movement Toggle 2") })
    sec:AddSlider("Value Slider 1", { Min = 0, Max = 100, Default = 16, Flag = "move_v1", Callback = stub("Value Slider 1") })
    sec:AddSlider("Value Slider 2", { Min = 0, Max = 200, Default = 50, Flag = "move_v2", Callback = stub("Value Slider 2") })
end

do
    local sec = Player:CreateSection("Character", false)
    sec:AddToggle("Character Toggle", { Bindable = false, Flag = "char_1", Callback = stub("Character Toggle") })
    sec:AddButton("Character Button", stub("Character Button"))
    sec:AddKeybind("Character Keybind", { Default = Enum.KeyCode.F, Flag = "char_key", Callback = stub("Character Keybind") })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Visuals
-- ───────────────────────────────────────────────────────────────────────────
local Visuals = Window:CreateTab("Visuals", { Icon = "☄️" })

do
    local sec = Visuals:CreateSection("Glow", true)
    sec:AddToggle("Enable Glow", { Bindable = false, Flag = "vis_glow", Callback = stub("Enable Glow") })
    sec:AddColorPicker("Glow Color", {
        Default = Color3.fromRGB(90, 210, 255), Flag = "vis_glow_color", Callback = stub("Glow Color"),
    })
    sec:AddSlider("Glow Strength", { Min = 0, Max = 100, Default = 40, Suffix = "%", Flag = "vis_glow_str", Callback = stub("Glow Strength") })
end

do
    local sec = Visuals:CreateSection("Overlay", false)
    sec:AddToggle("Overlay Toggle 1", { Bindable = false, Flag = "vis_o1", Callback = stub("Overlay Toggle 1") })
    sec:AddToggle("Overlay Toggle 2", { Bindable = false, Flag = "vis_o2", Callback = stub("Overlay Toggle 2") })
    sec:AddDropdown("Style:", { Options = { "Style 1", "Style 2", "Style 3" }, Default = "Style 1", Flag = "vis_style", Callback = stub("Style") })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Misc
-- ───────────────────────────────────────────────────────────────────────────
local Misc = Window:CreateTab("Misc", { Icon = "🌌" })

do
    local sec = Misc:CreateSection("Utilities", true)
    sec:AddButton("Utility Button 1", stub("Utility Button 1"))
    sec:AddButton("Utility Button 2", stub("Utility Button 2"))
    sec:AddTextbox("Input", { Placeholder = "type something...", Flag = "misc_input", Callback = stub("Input") })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Settings
-- ───────────────────────────────────────────────────────────────────────────
-- The free-tier editor owns a dedicated sidebar tab; staff controls are only
-- constructed after the server authorizes this session.
local Editor = TagEditor.Build(Window, Nametags)
local StaffPanel = staffAuthorized and AdminPanel and AdminPanel.Build(Window, ctx) or nil
local TagManagerPanel = (tagManagerAuthorized and not staffAuthorized and TagPanel) and TagPanel.Build(Window, ctx) or nil
local SupportStaffPanel = (supportAuthorized and not staffAuthorized and not tagManagerAuthorized and SupportPanel) and SupportPanel.Build(Window, ctx) or nil

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
