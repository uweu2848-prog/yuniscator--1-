-- ───────────────────────────────────────────────────────────────────────────
--  Load the UI library
-- ───────────────────────────────────────────────────────────────────────────
-- Raw URL format:  https://raw.githubusercontent.com/<user>/<repo>/<branch>/<file>
-- (NOT the github.com page link and NOT the .git clone link – those don't return the script text)
-- The repo must be PUBLIC or the game can't download it.
local LIB_URL = "https://raw.githubusercontent.com/uweu2848-prog/sliver-surfer-test/main/ScorpLib.lua"

local function loadLib()
    -- Local testing instead:  local src = readfile("ScorpLib.lua")
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

-- Prints what a control did, so you can see the UI is wired up before real features exist.
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
    Theme        = "Silver Surfer",           -- Silver Surfer | Power Cosmic | Zenn-La | Deep Space
    ToggleKey    = Enum.KeyCode.RightShift,   -- show / hide
    UnloadKey    = Enum.KeyCode.Delete,       -- destroy the UI
    WidgetText   = "Scorp",                   -- floating open button
    ConfigFolder = "Scorp",
    -- Starfield = false,                     -- turn the twinkling stars off
    BackgroundImage = "rbxassetid://0",       -- TODO: paste your uploaded key-art decal id here
    BackgroundImageTransparency = 0.5,        -- lower = more visible art, higher = more subtle
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
--  Misc
-- ───────────────────────────────────────────────────────────────────────────
local Misc = Window:CreateTab("Misc", { Icon = "🌌" })

do
    local sec = Misc:CreateSection("Utilities", true)
    sec:AddButton("Utility Button 1", stub("Utility Button 1"))                                             -- TODO
    sec:AddButton("Utility Button 2", stub("Utility Button 2"))                                             -- TODO
    sec:AddTextbox("Input", { Placeholder = "type something...", Flag = "misc_input", Callback = stub("Input") })  -- TODO
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
--  Cleanup (runs when the UI is unloaded – stop your loops / disconnect events here)
-- ───────────────────────────────────────────────────────────────────────────
Window:OnUnload(function()
    print("[Scorp] unloaded")
    -- TODO: undo anything your features changed
end)

Window:Notify("Scorp", "Loaded. Press " .. Window.ToggleKey.Name .. " to toggle.", 4)
