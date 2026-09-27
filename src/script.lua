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

-- Tag editor (live preview + export/import codes; lives in src/tageditor.lua)
local TagEditor = (function()
--@include tageditor.lua
end)()

-- ───────────────────────────────────────────────────────────────────────────
--  UI library (delivered by the server over the authenticated session)
-- ───────────────────────────────────────────────────────────────────────────
local libFn, libErr = ctx.loadstring(ctx.lib)
assert(libFn, "[Scorp] UI library failed to compile: " .. tostring(libErr))
local Scorp = libFn()
assert(Scorp, "[Scorp] UI library ran but returned nothing.")
ctx.lib = nil -- don't keep the library source sitting in the shared table

local Window
local splash
if Scorp.CreateSplash then
    splash = Scorp:CreateSplash({ Kind = "load" })
    task.wait()
end

local Features = (function()
--@include features.lua
end)()

local function note(title, text, bad)
    Window:Notify(title, tostring(text or ""), 3, bad and Window.Theme.Danger or nil)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Window
-- ───────────────────────────────────────────────────────────────────────────
Window = Scorp:CreateWindow({
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
    StartHidden  = splash ~= nil,
})

Window:SetWatermark('<font color="rgb(80,105,255)">Scorp</font>  ·  Made By Yuniku')

-- Start nametag sync BEFORE building the tag editor below, so its "load my saved
-- design" step has a real session (cfg) to sync with instead of racing it.
ctx.revoke = function()
    pcall(function() Window:Destroy(true) end)
end
Nametags.Start({
    ctx = ctx,
    request = ctx.request,
    server = ctx.server,
    onRevoked = function() ctx.revoke() end,
})

-- ───────────────────────────────────────────────────────────────────────────
--  Home
-- ───────────────────────────────────────────────────────────────────────────
local Home = Window:CreateTab("Home", { Icon = "🏠" })

do
    local sec = Home:CreateSection("Scorp", true)
    sec:AddLabel("Made by Yuniku.", { Wrap = true })
    sec:AddLabel("K hides the menu. Delete unloads it. The key chip on a row changes that bind.", { Wrap = true, Color = Window.Theme.TextDim })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Movement
-- ───────────────────────────────────────────────────────────────────────────
local Movement = Window:CreateTab("Movement", { Icon = "🏃" })

do
    local sec = Movement:CreateSection("Speed", true)
    sec:AddToggle("CFrame movement", {
        Keybind = Enum.KeyCode.C, Flag = "misc_cframe",
        Callback = function(on) Features.SetCFrame(on) end,
    })
    sec:AddSlider("CFrame speed", {
        Min = 0, Max = 500, Default = 16, Increment = 1, Flag = "misc_cframe_speed",
        Callback = function(v) Features.SetCFrameSpeed(v) end,
    })
    sec:AddSlider("Walk speed", {
        Min = 0, Max = 500, Default = 16, Increment = 1, Flag = "misc_ws",
        Callback = function(v) Features.SetWalkSpeed(v) end,
    })
end

do
    local sec = Movement:CreateSection("Flight", true)
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
    sec:AddSlider("Jump power", {
        Min = 0, Max = 500, Default = 50, Increment = 1, Flag = "misc_jp",
        Callback = function(v) Features.SetJumpPower(v) end,
    })
end

do
    local sec = Movement:CreateSection("Spin", true)
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
    local sec = Movement:CreateSection("Hover", true)
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
end

-- ───────────────────────────────────────────────────────────────────────────
--  Players
-- ───────────────────────────────────────────────────────────────────────────
local PlayersTab = Window:CreateTab("Players", { Icon = "👤" })
local playerBox

do
    local sec = PlayersTab:CreateSection("Target", true)
    playerBox = sec:AddTextbox("Player", {
        Placeholder = "name or display name", Flag = "misc_player", CallOnBlur = true,
    })
    sec:AddButton("Teleport", function() note("Players", Features.TeleportTo(playerBox:Get())) end)
    sec:AddButton("Behind", function() note("Players", Features.Behind(playerBox:Get())) end)
    sec:AddButton("Spectate / stop", function() note("Players", Features.Spectate(playerBox:Get())) end)
end

do
    local sec = PlayersTab:CreateSection("Attach", true)
    sec:AddLabel("Uses the name in Target.", { Color = Window.Theme.TextDim })
    sec:AddButton("Head sit", function() note("Players", Features.SetCarry("head", playerBox:Get())) end)
    sec:AddButton("Backpack", function() note("Players", Features.SetCarry("back", playerBox:Get())) end)
    sec:AddButton("Focus TP", function() note("Players", Features.SetCarry("focus", playerBox:Get())) end)
end

do
    local sec = PlayersTab:CreateSection("Coordinates", true)
    local xBox = sec:AddTextbox("X", { Placeholder = "X", Flag = "misc_x" })
    local yBox = sec:AddTextbox("Y", { Placeholder = "Y", Flag = "misc_y" })
    local zBox = sec:AddTextbox("Z", { Placeholder = "Z", Flag = "misc_z" })
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
    local sec = PlayersTab:CreateSection("Self", true)
    sec:AddToggle("Invisible (client)", {
        Bindable = true, Flag = "misc_invis",
        Callback = function(on) Features.SetInvisible(on) end,
    })
end

-- ───────────────────────────────────────────────────────────────────────────
--  Visuals
-- ───────────────────────────────────────────────────────────────────────────
local Visuals = Window:CreateTab("Visuals", { Icon = "👁️" })

do
    local sec = Visuals:CreateSection("ESP", true)
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
    local sec = Visuals:CreateSection("Hitbox", true)
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
    local sec = Visuals:CreateSection("Lighting", true)
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
end

do
    local sec = Visuals:CreateSection("Camera", true)
    sec:AddToggle("Freecam", {
        Bindable = true, Flag = "misc_fc",
        Callback = function(on) Features.SetFreecam(on) end,
    })
    sec:AddSlider("FOV", {
        Min = 1, Max = 120, Default = 70, Increment = 1, Flag = "misc_fov",
        Callback = function(v) Features.SetFov(v) end,
    })
    sec:AddToggle("Lock FOV", {
        Bindable = true, Flag = "misc_lockfov",
        Callback = function(on) Features.SetLockFov(on) end,
    })
    sec:AddButton("First person", function() Features.FirstPerson() note("Camera", "first person") end)
    sec:AddButton("Third person", function() Features.ThirdPerson() note("Camera", "third person") end)
    sec:AddButton("Reset camera", function() Features.FixCam() note("Camera", "camera reset") end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  World
-- ───────────────────────────────────────────────────────────────────────────
local World = Window:CreateTab("World", { Icon = "🌍" })

do
    local sec = World:CreateSection("Gravity", true)
    sec:AddToggle("Custom gravity", {
        Keybind = Enum.KeyCode.G, Flag = "misc_grav",
        Callback = function(on) Features.SetGravity(on) end,
    })
    sec:AddSlider("Gravity", {
        Min = 0, Max = 500, Default = 196, Increment = 1, Flag = "misc_grav_v",
        Callback = function(v) Features.SetCustomGravity(v) end,
    })
end

do
    local sec = World:CreateSection("Safety", true)
    sec:AddToggle("Anti-fling", {
        Bindable = true, Flag = "misc_antifling",
        Callback = function(on) Features.SetAntifling(on) end,
    })
    sec:AddToggle("Anti-void", {
        Bindable = true, Flag = "misc_void",
        Callback = function(on) Features.SetAntivoid(on) end,
    })
end

do
    local sec = World:CreateSection("Map", true)
    sec:AddButton("Infbaseplate", function()
        note("World", Features.ToggleInfBaseplate())
    end)
end

do
    local sec = World:CreateSection("Voice", true)
    sec:AddLabel("Click Anti VC, then unmute. It finishes once the mic is live.", { Wrap = true, Color = Window.Theme.TextDim })
    sec:AddButton("Anti VC", function()
        task.spawn(function()
            local ok, msg = Features.RunAntiVC(function(status)
                note("World", status)
            end)
            note("World", msg, not ok)
        end)
    end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Staff
-- ───────────────────────────────────────────────────────────────────────────
local Staff = Window:CreateTab("Staff", { Icon = "🛡️" })

local staffTarget
local function staffAct(cmd, label)
    local ok, msg = Features.StaffAction(cmd, staffTarget:Get())
    note("Staff", ok and (label .. " sent") or msg, not ok)
end

do
    local sec = Staff:CreateSection("Target", true)
    local status = sec:AddLabel("Staff: loading…", { Wrap = true, Color = Window.Theme.TextDim })
    task.spawn(function()
        Features.Start({ request = ctx.request })
        status:Set(Features.StaffStatus())
    end)
    staffTarget = sec:AddTextbox("Target", {
        Placeholder = "username (blank = everyone)", Flag = "misc_staff_target", CallOnBlur = true,
    })
    sec:AddButton("Refresh staff list", function()
        local msg = Features.RefreshStaff()
        status:Set(msg)
        note("Staff", msg, not Features.IsStaff())
    end)
end

do
    local sec = Staff:CreateSection("Move", true)
    sec:AddButton("Flywheel", function() staffAct("fw", "flywheel") end)
    sec:AddButton("Bring to me", function()
        if staffTarget:Get() == "" then
            note("Staff", "bring needs a specific player", true)
            return
        end
        staffAct("brg", "bring")
    end)
    sec:AddButton("Sit", function() staffAct("sit", "sit") end)
    sec:AddButton("Jump", function() staffAct("jmp", "jump") end)
    sec:AddButton("Spin on", function() staffAct("spn", "spin") end)
    sec:AddButton("Spin off", function() staffAct("usp", "unspin") end)
end

do
    local sec = Staff:CreateSection("Control", true)
    sec:AddButton("Freeze", function() staffAct("frz", "freeze") end)
    sec:AddButton("Unfreeze", function() staffAct("thw", "unfreeze") end)
    sec:AddButton("Blind", function() staffAct("bld", "blind") end)
    sec:AddButton("Unblind", function() staffAct("ubl", "unblind") end)
end

do
    local sec = Staff:CreateSection("Remove", true)
    sec:AddButton("Fling", function() staffAct("flg", "fling") end)
    sec:AddButton("Void", function() staffAct("vod", "void") end)
    sec:AddButton("Reset", function() staffAct("rst", "reset") end)
    sec:AddButton("Kick", function() staffAct("kck", "kick") end)
end

local Keybinds = Window:CreateTab("Keybinds", { Icon = "⌨️" })

-- ───────────────────────────────────────────────────────────────────────────
--  Settings
-- ───────────────────────────────────────────────────────────────────────────
-- Tag Editor: its own standalone window (not a sidebar tab) — opened from the
-- info bar's 🏷️ button, or from Settings below. Save My Tag persists it server-side.
local EditorPanel = Window:CreatePopout({
    Name = "TagEditor", Title = "🎨  Nametag Editor", Size = UDim2.fromOffset(460, 560),
})
local Editor = TagEditor.Build(Window, Nametags, { Host = EditorPanel })

local Settings = Window:CreateTab("Settings", { Icon = "⚙️" })

Window:AddThemeControls(Settings, "🎨 Theme")
Window:AddConfigControls(Settings, "💾 Configs")

do
    local sec = Settings:CreateSection("Menu", true)
    sec:AddKeybind("Menu Toggle Key", {
        Default  = Window.ToggleKey,
        OnChange = function(key) Window:SetToggleKey(key) end,
    })
    sec:AddButton("Open Nametag Editor", function() Editor.Show() end)
end

Window:MountKeybindTab(Keybinds)

-- ───────────────────────────────────────────────────────────────────────────
--  Info bar — player count (+1/-1 on join/leave), ping, fps, and quick icons.
--  Always visible, independent of the main panel — set DISCORD_INVITE below to
--  wire up the 💬 button (defaults to just copying the invite link to clipboard).
-- ───────────────────────────────────────────────────────────────────────────
local DISCORD_INVITE = "https://discord.gg/YOUR_INVITE_HERE"

local InfoBar = Window:CreateInfoBar({
    OnSettings = function()
        Window:Toggle(true)
        Window:SelectTab(Settings)
    end,
    OnNametag = function() Editor.Toggle() end,
    OnDiscord = function()
        local fn = setclipboard or toclipboard
        if type(fn) == "function" and pcall(fn, DISCORD_INVITE) then
            Window:Notify("Discord", "Invite link copied to clipboard.", 3)
        else
            Window:Notify("Discord", DISCORD_INVITE, 5)
        end
    end,
})

-- ───────────────────────────────────────────────────────────────────────────
--  Nametag settings
-- ───────────────────────────────────────────────────────────────────────────
do
    local sec = Settings:CreateSection("Nametags", true)
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
end

-- ───────────────────────────────────────────────────────────────────────────
--  Session hooks + cleanup
-- ───────────────────────────────────────────────────────────────────────────
Window:OnUnload(function()
    print("[Scorp] unloaded")
    pcall(Features.Cleanup)
    pcall(Editor.Destroy)
    pcall(function() if EditorPanel.Frame then EditorPanel.Frame:Destroy() end end)
    pcall(InfoBar.Destroy)
    Nametags.Stop()
end)

local function announce()
    local toggleName = (Window.ToggleKey and Window.ToggleKey.Name) or "None"
    Window:Notify("Scorp", "Loaded. Press " .. toggleName .. " to toggle.", 4)
end
if splash then
    splash:Play(function()
        Window:Toggle(true)
        announce()
    end)
else
    announce()
end