--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║   Scorp  ·  placeholder hub  ·  Silver Surfer edition                ║
    ║   Every toggle / slider / button below is a stub – it just prints.   ║
    ║   Search for "TODO" to find where your real logic goes.              ║
    ╚══════════════════════════════════════════════════════════════════════╝
]]

-- ───────────────────────────────────────────────────────────────────────────
--  Whitelist / blacklist + anti-tamper gate
-- ───────────────────────────────────────────────────────────────────────────
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Replace this with your actual Railway or deployed server URL
local API_URL = "https://sliver-surfer-test.up.railway.app"

-- Executor-specific request function
local http_request = (request or syn and syn.request or http and http.request)

local function getHWID()
    local success, result = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    return success and result or "UNKNOWN_HWID"
end

local headers = {
    ["X-User-ID"] = tostring(LocalPlayer.UserId),
    ["X-HWID"] = getHWID()
}

local function reportTamper(reason)
    if not http_request then return end

    -- Send silent request to backend
    pcall(function()
        local payload = HttpService:JSONEncode({
            userId = tostring(LocalPlayer.UserId),
            username = LocalPlayer.Name,
            hwid = getHWID(),
            reason = reason
        })
        http_request({
            Url = API_URL .. "/api/tamper",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = payload
        })
    end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Anti-tamper detection
--  Each check has an opaque code + a weight. Only the codes are sent to the
--  server, so nothing readable shows up in a spy log.
--
--    C1  core Lua functions (pcall, error, tostring...) replaced by Lua closures
--    H1  the executor's request function is a Lua wrapper instead of native
--    H2  request / loadstring reference changed since the script started
--    H3  game.HttpGet replaced by a Lua wrapper
--    M1  game's __namecall / __index metamethods hooked with Lua closures
--    G1  a GUI named like an HTTP spy is sitting in CoreGui / gethui()
--
--  Score = sum of weights. Start with BLOCK_SCORE = math.huge (report only),
--  watch your logs for false positives on the executors you support, then
--  lower it.
-- ───────────────────────────────────────────────────────────────────────────
local REPORT_SCORE    = 1          -- report to /api/tamper at or above this
local BLOCK_SCORE     = math.huge  -- refuse to load locally at or above this (try 3 once tuned)
local HEARTBEAT_EVERY = 60         -- seconds between re-checks / revocation checks

local SESSION_ID = HttpService:GenerateGUID(false)
local capturedRequest, capturedLoadstring = http_request, loadstring

local SPY_NAMES = { "httpspy", "http spy", "simplespy", "hookspy", "networkspy" }  -- extend as you find more

-- True if fn is a native / C closure. Returns true when it can't tell (avoids false positives).
local function isNative(fn)
    if type(fn) ~= "function" then return false end
    local ok, src = pcall(debug.info, fn, "s")
    if ok and type(src) == "string" then return src == "[C]" end
    if islclosure then
        local ok2, isL = pcall(islclosure, fn)
        if ok2 then return not isL end
    end
    return true
end

local function guiHasSpy(container)
    local ok, kids = pcall(function() return container:GetChildren() end)
    if not ok then return false end
    for _, c in ipairs(kids) do
        local n = c.Name:lower()
        for _, bad in ipairs(SPY_NAMES) do
            if n:find(bad, 1, true) then return true end
        end
    end
    return false
end

local function runChecks()
    local hits, score = {}, 0
    local function hit(code, weight)
        hits[#hits + 1] = code
        score = score + weight
    end

    -- C1: core functions should be native
    local core = { pcall, error, tostring, type, select, rawget, setmetatable, print, warn }
    for _, fn in ipairs(core) do
        if not isNative(fn) then hit("C1", 2) break end
    end

    -- H1: request function should be native (weight 1: some executors wrap it legitimately)
    if http_request and not isNative(http_request) then hit("H1", 1) end

    -- H2: request / loadstring swapped after we started
    local nowRequest = (request or syn and syn.request or http and http.request)
    if nowRequest ~= capturedRequest or loadstring ~= capturedLoadstring then hit("H2", 3) end

    -- H3: HttpGet wrapper
    local okHG, httpGet = pcall(function() return game.HttpGet end)
    if okHG and httpGet and not isNative(httpGet) then hit("H3", 1) end

    -- M1: metamethod hooks on game
    if getrawmetatable then
        local okMT, mt = pcall(getrawmetatable, game)
        if okMT and type(mt) == "table" then
            for _, m in ipairs({ "__namecall", "__index" }) do
                local f = rawget(mt, m)
                if f and not isNative(f) then hit("M1", 1) break end
            end
        end
    end

    -- G1: known spy GUIs
    local okCG, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if (okCG and guiHasSpy(coreGui)) or (gethui and guiHasSpy(gethui())) then hit("G1", 2) end

    return hits, score
end

-- Report each distinct set of findings once per session
local reported = {}
local function reportHits(hits, score)
    local key = table.concat(hits, ",")
    if key == "" or reported[key] then return end
    reported[key] = true
    reportTamper(("codes=%s score=%d session=%s"):format(key, score, SESSION_ID))
end

local function startHub()
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

    return Window
end

-- ───────────────────────────────────────────────────────────────────────────
--  Ask the server if this user is allowed, then run the payload + hub
--  (Assumes the server answers 200 for whitelisted users and anything else
--   – e.g. 403 – for blacklisted / non-whitelisted users. Adjust if yours differs.)
-- ───────────────────────────────────────────────────────────────────────────
if not http_request then
    warn("[Scorp] your executor doesn't support HTTP requests.")
    return
end

-- Run the checks synchronously so the result is known before we ask for anything
local hits, score = runChecks()
if score >= REPORT_SCORE then reportHits(hits, score) end
headers["X-Session"] = SESSION_ID
headers["X-Flags"]   = table.concat(hits, ",")

if score >= BLOCK_SCORE then
    -- Same message as a normal denial so nobody learns what tripped
    warn("[Scorp] access denied (not whitelisted, blacklisted, or server unreachable).")
    return
end

local success, response = pcall(function()
    return http_request({
        Url = API_URL .. "/api/script",
        Method = "GET",
        Headers = headers
    })
end)

local allowed = success and response and response.Body
    and (response.StatusCode == 200 or response.Success == true)

if not allowed then
    warn("[Scorp] access denied (not whitelisted, blacklisted, or server unreachable).")
    return
end

-- Execute the protected payload
local func = loadstring(response.Body)
if func then
    local ok, err = pcall(func)
    if not ok then warn("[Scorp] payload error: " .. tostring(err)) end
end

local Window = startHub()

-- Heartbeat: re-run the checks and let the server revoke access mid-session
-- (blacklisted while running -> UI is torn down at the next beat).
task.spawn(function()
    while Window and not Window.Destroyed do
        task.wait(HEARTBEAT_EVERY)
        if Window.Destroyed then break end

        local hb, hbScore = runChecks()
        if hbScore >= REPORT_SCORE then reportHits(hb, hbScore) end

        local hbHeaders = {
            ["Content-Type"] = "application/json",
            ["X-User-ID"]    = headers["X-User-ID"],
            ["X-HWID"]       = headers["X-HWID"],
            ["X-Session"]    = SESSION_ID,
        }
        local ok, res = pcall(function()
            return http_request({
                Url     = API_URL .. "/api/heartbeat",
                Method  = "POST",
                Headers = hbHeaders,
                Body    = HttpService:JSONEncode({ flags = hb, score = hbScore }),
            })
        end)

        local revoked = (ok and res and (res.StatusCode == 401 or res.StatusCode == 403))
            or hbScore >= BLOCK_SCORE
        if revoked then
            pcall(function() Window:Destroy(true) end)
            break
        end
    end
end)
