local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local API_URL = "https://sliver-surfer-test.up.railway.app:8080"
local LocalPlayer = Players.LocalPlayer
local userId = tostring(LocalPlayer.UserId)
local username = LocalPlayer.Name
local isScriptActive = true

-- ───────────────────────────────────────────────────────────────────────────
--  Load the UI library
-- ───────────────────────────────────────────────────────────────────────────
-- Raw URL format:  https://raw.githubusercontent.com/<user>/<repo>/<branch>/<file>
local LIB_URL = "https://raw.githubusercontent.com/uweu2848-prog/yuniscator--1-/refs/heads/main/ScorpLib.lua"

local function loadLib()
    local ok, src = pcall(function() return game:HttpGet(LIB_URL) end)
    assert(ok, "[Scorp] couldn't download the library (check URL / branch / repo is public): " .. tostring(src))

    local fn, err = loadstring(src)
    assert(fn, "[Scorp] library downloaded (" .. #src .. " bytes) but failed to compile: " .. tostring(err)
        .. "\nFirst 80 chars: " .. src:sub(1, 80))

    local lib = fn()
    assert(lib, "[Scorp] library ran but returned nothing – downloaded " .. #src
        .. " bytes (full ScorpLib.lua is ~72,000). Wrong or incomplete file at that URL.\nLast 80 chars: " .. src:sub(-80))
    return lib
end

local Scorp = loadLib()

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
    Subtitle     = "A Out Of Space Experince. ~Made By Yuniku.  ·  v0.1",
    Theme        = "Silver Surfer",
    ToggleKey    = Enum.KeyCode.RightShift,
    UnloadKey    = Enum.KeyCode.Delete,
    WidgetText   = "Scorp",
    ConfigFolder = "Scorp",
    BackgroundImage = "rbxassetid://0",
    BackgroundImageTransparency = 0.5,
})

Window:SetWatermark('<font color="rgb(168,186,214)">Scorp</font>  ·  placeholder build')

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
--  Server Presence & Tag System
-- ───────────────────────────────────────────────────────────────────────────
local function registerOnline()
    pcall(function()
        game:HttpPost(
            API_URL .. "/api/users/online",
            HttpService:JSONEncode({ }),
            Enum.HttpContentType.ApplicationJson,
            false,
            { ["X-User-ID"] = userId, ["X-User-Name"] = username }
        )
    end)
end

local function unregisterOnline()
    pcall(function()
        game:HttpPost(
            API_URL .. "/api/users/offline",
            HttpService:JSONEncode({ }),
            Enum.HttpContentType.ApplicationJson,
            false,
            { ["X-User-ID"] = userId }
        )
    end)
end

registerOnline()

local playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        unregisterOnline()
    end
end)

task.spawn(function()
    while isScriptActive do
        task.wait(5)
        if not isScriptActive then break end
        
        local ok, response = pcall(function()
            return game:HttpGet(API_URL .. "/api/users/online")
        end)
        
        if ok and response then
            local data = HttpService:JSONDecode(response)
            for _, user in ipairs(data.allUsers) do
                local player = Players:FindFirstChild(user.username)
                if player and player.Character then
                    local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                    if humanoidRootPart then
                        local tagLabel = humanoidRootPart:FindFirstChild("TagLabel")
                        if not tagLabel then
                            tagLabel = Instance.new("BillboardGui")
                            tagLabel.Name = "TagLabel"
                            tagLabel.Size = UDim2.new(4, 0, 2, 0)
                            tagLabel.MaxDistance = 100
                            tagLabel.Parent = humanoidRootPart
                            
                            local textLabel = Instance.new("TextLabel")
                            textLabel.BackgroundTransparency = 0.3
                            textLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                            textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                            textLabel.TextSize = 14
                            textLabel.Size = UDim2.new(1, 0, 1, 0)
                            textLabel.Parent = tagLabel
                        end
                        
                        local textLabel = tagLabel:FindFirstChild("TextLabel")
                        textLabel.Text = user.isOwner and "👑 OWNER" or "MEMBER"
                        textLabel.TextColor3 = user.isOwner and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(200, 200, 200)
                    end
                end
            end
        end
    end
end)

-- ───────────────────────────────────────────────────────────────────────────
--  Cleanup
-- ───────────────────────────────────────────────────────────────────────────
Window:OnUnload(function()
    print("[Scorp] unloaded")
    
    -- Disconnect API connections and stop loops
    isScriptActive = false
    if playerRemovingConnection then
        playerRemovingConnection:Disconnect()
    end
    unregisterOnline()
    
    -- Delete all created tags from players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local tag = player.Character.HumanoidRootPart:FindFirstChild("TagLabel")
            if tag then tag:Destroy() end
        end
    end
end)

Window:Notify("Scorp", "Loaded. Press " .. Window.ToggleKey.Name .. " to toggle.", 4)