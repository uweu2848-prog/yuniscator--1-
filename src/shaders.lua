-- Yuniku-inspired local visual engine for the Scorp client.
-- Roblox does not expose custom GPU shaders, true SSR, or TAA to LocalScripts;
-- these are reversible post-processing, screen-space overlays, and raycast approximations.
local Shaders = {}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local PRESETS = {
    ["Unreal"] = {
        tint = Color3.fromRGB(255, 248, 238), saturation = 0.25, contrast = 0.35,
        brightness = 0, bloom = 0.3, threshold = 1.8, dof = 0.08,
        atmosphere = 0.22, vignette = 0.62, grain = 0.92, chroma = 0.94,
    },
    ["Cinematic"] = {
        tint = Color3.fromRGB(255, 244, 232), saturation = 0.15, contrast = 0.45,
        brightness = 0, bloom = 0.2, threshold = 1.8, dof = 0.12,
        atmosphere = 0.2, vignette = 0.55, grain = 0.88, chroma = 0.9,
    },
    ["Bodycam"] = {
        tint = Color3.fromRGB(160, 175, 165), saturation = -0.55, contrast = 0.7,
        brightness = 0, bloom = 0.3, threshold = 1.2, dof = 0.05,
        atmosphere = 0.14, vignette = 0.35, grain = 0.8, chroma = 0.96,
    },
}

local function make(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end

function Shaders.Build(Window)
    local tab = Window:CreateTab("Shaders", { Icon = "✨", Group = "Studio" })
    local engine = {
        Active = false,
        Preset = nil,
        Connections = {},
        Effects = {},
        Overlays = {},
        Motes = {},
        Stats = { indoors = false, water = false, neon = 0, frameMs = 0, quality = "High" },
        Options = { overlays = true, adaptive = true, particles = true, quality = "High" },
        ScanClock = 0,
        AdaptedExposure = 0,
        SlowFrames = 0,
        FastFrames = 0,
        DynamicQuality = false,
    }

    local statusLabel
    local statsLabel

    local function status(text)
        if statusLabel then statusLabel:Set(text) end
    end

    local function destroyOwned()
        for _, connection in ipairs(engine.Connections) do
            pcall(function() connection:Disconnect() end)
        end
        engine.Connections = {}
        for _, object in ipairs(engine.Effects) do
            pcall(function() object:Destroy() end)
        end
        engine.Effects = {}
        if engine.Gui then pcall(function() engine.Gui:Destroy() end) end
        engine.Gui = nil
        engine.Overlays = {}
        engine.Motes = {}
    end

    local function stop()
        engine.Active = false
        destroyOwned()
        engine.Preset = nil
        status("Engine stopped · original game effects left untouched.")
    end

    local function createGui(profile)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
        local gui = make("ScreenGui", {
            Name = "ScorpYunikuShaderOverlay",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 20,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, playerGui)
        engine.Gui = gui

        local vignette = make("ImageLabel", {
            Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Image = "rbxassetid://4576475446", ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = profile.vignette, ScaleType = Enum.ScaleType.Stretch,
            ZIndex = 1,
        }, gui)
        engine.Overlays.vignette = vignette
        local grain = make("ImageLabel", {
            Name = "FilmGrain", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Image = "rbxassetid://13807207441", ImageTransparency = profile.grain,
            ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(250, 250), ZIndex = 3,
        }, gui)
        engine.Overlays.grain = grain
        local chromaRed = make("ImageLabel", {
            Name = "ChromaticRed", Size = UDim2.fromScale(1.02, 1.02), Position = UDim2.fromScale(-0.01, -0.01),
            BackgroundTransparency = 1, Image = "rbxassetid://4576475446", ImageColor3 = Color3.fromRGB(255, 0, 0),
            ImageTransparency = 1, ZIndex = 2,
        }, gui)
        engine.Overlays.chromaRed = chromaRed
        local chromaBlue = make("ImageLabel", {
            Name = "ChromaticBlue", Size = UDim2.fromScale(1.02, 1.02), Position = UDim2.fromScale(0.01, 0.01),
            BackgroundTransparency = 1, Image = "rbxassetid://4576475446", ImageColor3 = Color3.fromRGB(0, 50, 255),
            ImageTransparency = 1, ZIndex = 2,
        }, gui)
        engine.Overlays.chromaBlue = chromaBlue
        local flare = make("ImageLabel", {
            Name = "SunFlare", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(300, 300),
            BackgroundTransparency = 1, Image = "rbxassetid://1315865215", ImageColor3 = Color3.fromRGB(255, 220, 170),
            ImageTransparency = 1, ZIndex = 4,
        }, gui)
        engine.Overlays.flare = flare

        local count = engine.Options.quality == "Low" and 8 or (engine.Options.quality == "Medium" and 16 or 28)
        for i = 1, count do
            local mote = make("Frame", {
                Name = "DustMote", AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(math.random(), math.random()),
                Size = UDim2.fromOffset(math.random(1, 3), math.random(1, 3)),
                BackgroundColor3 = Color3.fromRGB(255, 238, 205),
                BackgroundTransparency = 0.55 + math.random() * 0.4,
                BorderSizePixel = 0, Visible = engine.Options.particles, ZIndex = 5,
            }, gui)
            make("UICorner", { CornerRadius = UDim.new(1, 0) }, mote)
            engine.Motes[#engine.Motes + 1] = { gui = mote, drift = (math.random() - 0.5) * 0.003 }
        end
    end

    local function addEffect(className, name, properties)
        local effect = make(className, properties, Lighting)
        effect.Name = name
        engine.Effects[#engine.Effects + 1] = effect
        return effect
    end

    local function safeScan(camera)
        if not camera then return end
        local character = LocalPlayer.Character
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character, camera }
        local origin = camera.CFrame.Position
        local directions = {
            Vector3.new(0, -1, 0), camera.CFrame.LookVector,
            camera.CFrame.RightVector, -camera.CFrame.RightVector,
            Vector3.new(0, 1, 0),
        }
        local indoorHits, closeHits, neonCount, neonColor, hitCount = 0, 0, 0, Color3.new(0, 0, 0), 0
        local brightnessSum, materialCounts, focusDistance = 0, {}, 350
        for _, direction in ipairs(directions) do
            local ok, result = pcall(function()
                return workspace:Raycast(origin, direction.Unit * 60, params)
            end)
            if ok and result then
                hitCount = hitCount + 1
                if direction.Y > 0.5 then indoorHits = indoorHits + 1 end
                local part = result.Instance
                if result.Distance < 8 then closeHits = closeHits + 1 end
                brightnessSum = brightnessSum + (part.Color.R * 0.2126 + part.Color.G * 0.7152 + part.Color.B * 0.0722)
                local materialName = part.Material.Name
                materialCounts[materialName] = (materialCounts[materialName] or 0) + 1
                if part and (part.Material == Enum.Material.Neon or part.Material == Enum.Material.ForceField) then
                    neonCount = neonCount + 1
                    neonColor = neonColor + part.Color
                end
                if direction == directions[2] then focusDistance = result.Distance end
            end
        end
        local mainMaterial, mainCount = "Unknown", 0
        for materialName, count in pairs(materialCounts) do
            if count > mainCount then mainMaterial, mainCount = materialName, count end
        end
        local water = false
        local waterOk, waterResult = pcall(function()
            return workspace:Raycast(origin, Vector3.new(0, -18, 0), params)
        end)
        if waterOk and waterResult and waterResult.Instance then
            water = waterResult.Instance.Material == Enum.Material.Water
                or string.find(string.lower(waterResult.Instance.Name), "water", 1, true) ~= nil
        end
        engine.Stats.indoors = indoorHits >= 1
        engine.Stats.water = water
        engine.Stats.neon = neonCount
        engine.Stats.hitCount = hitCount
        engine.Stats.neonColor = neonCount > 0 and neonColor / neonCount or Color3.new(0, 0, 0)
        engine.Stats.occlusion = math.clamp(1 - closeHits / math.max(#directions) * 0.15, 0.85, 1)
        engine.Stats.sceneLuminance = hitCount > 0 and brightnessSum / hitCount or 0.5
        engine.Stats.focusDistance = focusDistance
        engine.Stats.material = mainMaterial
    end

    local function update(dt)
        if not engine.Active then return end
        local camera = workspace.CurrentCamera
        if not camera or not engine.Preset then return end
        local profile = PRESETS[engine.Preset]
        engine.Stats.frameMs = dt * 1000
                if engine.Options.quality == "High" then
                    if dt > 0.025 then
                        engine.SlowFrames = engine.SlowFrames + 1
                        engine.FastFrames = 0
                    elseif dt < 0.018 then
                        engine.FastFrames = engine.FastFrames + 1
                        engine.SlowFrames = 0
                    else
                        engine.SlowFrames = math.max(0, engine.SlowFrames - 1)
                        engine.FastFrames = math.max(0, engine.FastFrames - 1)
                    end
                    if engine.SlowFrames >= 90 then engine.DynamicQuality = true end
                    if engine.FastFrames >= 180 then engine.DynamicQuality = false end
                else
                    engine.DynamicQuality = false
                end
        engine.ScanClock = engine.ScanClock + dt
        if engine.ScanClock >= 0.2 then
            engine.ScanClock = 0
            safeScan(camera)
        end

        local clock = Lighting.ClockTime
        local night = clock < 6 or clock > 18
        local sunset = (clock >= 17 and clock <= 19) or (clock >= 5 and clock <= 7)
        local dark = engine.Stats.indoors or night or (engine.Stats.sceneLuminance or 0.5) < 0.22
        local colorCorrection = engine.Effects[1]
        local bloom = engine.Effects[2]
        local dof = engine.Effects[3]
        local sunRays = engine.Effects[4]
        local atmosphere = engine.Effects[5]
        if not (colorCorrection and colorCorrection.Parent and bloom and bloom.Parent) then return end

        if engine.Options.adaptive then
            local targetExposure = dark and 0.08 or (sunset and -0.06 or profile.brightness)
            local eyeAdaptation = math.clamp((0.5 - (engine.Stats.sceneLuminance or 0.5)) * 0.22, -0.12, 0.12)
            local ambientOcclusion = engine.Stats.occlusion or 1
            local targetExposure = (dark and 0.08 or (sunset and -0.06 or profile.brightness)) + eyeAdaptation
            if engine.Stats.water then targetExposure = -0.12 end
            engine.AdaptedExposure = engine.AdaptedExposure + (targetExposure - engine.AdaptedExposure) * math.clamp(dt * 1.5, 0, 1)
            colorCorrection.Brightness = engine.AdaptedExposure
            colorCorrection.Contrast = math.clamp(profile.contrast + (1 - ambientOcclusion) * 0.2, 0, 0.8)
            if sunset then
                colorCorrection.TintColor = Color3.fromRGB(255, 218, 185)
            elseif engine.Stats.water then
                colorCorrection.TintColor = Color3.fromRGB(170, 210, 230)
            elseif engine.Stats.neon > 0 then
                colorCorrection.TintColor = profile.tint:Lerp(engine.Stats.neonColor, 0.08)
            else
                colorCorrection.TintColor = profile.tint
            end
            bloom.Intensity = math.clamp(profile.bloom + (engine.Stats.neon * 0.025), 0, 0.45)
                        bloom.Intensity = math.clamp(profile.bloom + (engine.Stats.neon * 0.025), 0, 0.45)
                        bloom.Size = engine.DynamicQuality and 14 or (engine.Options.quality == "Low" and 12 or 24)
            if atmosphere then
                atmosphere.Density = dark and 0.14 or (sunset and 0.27 or profile.atmosphere)
                atmosphere.Color = sunset and Color3.fromRGB(255, 180, 125) or Color3.fromRGB(205, 205, 215)
                atmosphere.Decay = sunset and Color3.fromRGB(170, 100, 75) or Color3.fromRGB(100, 110, 130)
            end
        end

        local focusRay
        pcall(function()
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { LocalPlayer.Character, camera }
            focusRay = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 350, params)
        end)
        if dof and engine.Options.adaptive then
            dof.FocusDistance = math.clamp(focusRay and (focusRay.Position - camera.CFrame.Position).Magnitude or 350, 8, 350)
            dof.InFocusRadius = math.clamp(dof.FocusDistance * 0.55, 18, 120)
            dof.FarIntensity = profile.dof
        end
        if sunRays then
            local sunDir = Lighting:GetSunDirection()
            local sunPoint, visible = camera:WorldToViewportPoint(camera.CFrame.Position + sunDir * 1000)
            local flare = engine.Overlays.flare
            if flare and engine.Options.overlays and visible and sunPoint.Z > 0 and not engine.Stats.indoors then
                flare.Visible = true
                flare.Position = UDim2.fromOffset(sunPoint.X, sunPoint.Y)
                flare.ImageTransparency = math.clamp(0.96 - math.max(0, camera.CFrame.LookVector:Dot(sunDir)) * 0.35, 0.55, 0.98)
                sunRays.Intensity = math.clamp(0.1 + math.max(0, camera.CFrame.LookVector:Dot(sunDir)) * 0.22, 0, 0.32)
            else
                if flare then flare.Visible = false end
                sunRays.Intensity = 0.08
            end
        end
        local vignette = engine.Overlays.vignette
        local grain = engine.Overlays.grain
        local chromaRed = engine.Overlays.chromaRed
        local chromaBlue = engine.Overlays.chromaBlue
        if vignette then vignette.Visible = engine.Options.overlays end
        if grain then grain.Visible = engine.Options.overlays end
        if chromaRed and chromaBlue then
            local intensity = engine.Options.overlays and math.clamp((profile.chroma and (1 - profile.chroma) or 0.08) + (engine.Stats.frameMs > 25 and 0.025 or 0), 0.02, 0.14) or 0
            chromaRed.ImageTransparency = 1 - intensity
            chromaBlue.ImageTransparency = 1 - intensity
        end
        for _, mote in ipairs(engine.Motes) do
            mote.gui.Visible = engine.Options.overlays and engine.Options.particles
            if mote.gui.Visible then
                local pos = mote.gui.Position
                local y = pos.Y.Scale + mote.drift
                if y > 1.02 then y = -0.02 elseif y < -0.02 then y = 1.02 end
                mote.gui.Position = UDim2.fromScale(pos.X.Scale, y)
            end
        end
        if statsLabel then
            statsLabel:Set(string.format(
            "Preset: %s  ·  FPS: %d\nEnvironment: %s%s  ·  Neon hits: %d\nSurface: %s · focus %.0f studs\nQuality: %s%s · Scan: %d",
                engine.Preset, math.floor(1000 / math.max(engine.Stats.frameMs, 1)),
                engine.Stats.indoors and "Indoor" or "Outdoor", engine.Stats.water and " · Underwater" or "",
                engine.Stats.neon, engine.Stats.material or "Unknown", engine.Stats.focusDistance or 0,
                engine.Options.quality, engine.DynamicQuality and " · adaptive" or "", engine.Stats.hitCount or 0))
        end
    end

    local function start(name)
        stop()
        local profile = PRESETS[name]
        if not profile then status("Unknown preset."); return end
        engine.Active = true
        engine.Preset = name
        engine.AdaptedExposure = profile.brightness
        local ok, err = pcall(function()
            addEffect("ColorCorrectionEffect", "ScorpYuniku_Color", {
                Enabled = true, TintColor = profile.tint, Saturation = profile.saturation,
                Contrast = profile.contrast, Brightness = profile.brightness,
            })
            addEffect("BloomEffect", "ScorpYuniku_Bloom", {
                Enabled = true, Intensity = profile.bloom, Size = 24, Threshold = profile.threshold,
            })
            addEffect("DepthOfFieldEffect", "ScorpYuniku_Depth", {
                Enabled = true, FocusDistance = 50, InFocusRadius = 35, NearIntensity = 0, FarIntensity = profile.dof,
            })
            addEffect("SunRaysEffect", "ScorpYuniku_SunRays", { Enabled = true, Intensity = 0.12, Spread = 0.75 })
            addEffect("Atmosphere", "ScorpYuniku_Atmosphere", {
                Density = profile.atmosphere, Offset = 0.25, Color = Color3.fromRGB(205, 205, 215),
                Decay = Color3.fromRGB(100, 110, 130), Glare = 0.2, Haze = 0.8,
            })
            createGui(profile)
            safeScan(workspace.CurrentCamera)
            engine.Connections[#engine.Connections + 1] = RunService.RenderStepped:Connect(update)
        end)
        if not ok then
            stop()
            status("Could not start shader engine · " .. tostring(err))
            return
        end
        status(name .. " profile active · local visual effects only.")
    end

    do
        local sec = tab:CreateSection("Yuniku Visual Engine", true)
        sec:AddLabel("Roblox uses post-processing and screen-space approximations here; true GPU shaders, SSR and TAA are not exposed to client scripts.", { Wrap = true, Color = Window.Theme.TextDim })
        statusLabel = sec:AddLabel("Engine stopped · original game effects left untouched.", { Wrap = true })
        sec:AddButton("Unreal Profile", function() start("Unreal") end)
        sec:AddButton("Cinematic Profile", function() start("Cinematic") end)
        sec:AddButton("Bodycam Profile", function() start("Bodycam") end)
        sec:AddButton("Stop Engine / Restore", stop)
    end

    do
        local sec = tab:CreateSection("Engine Options", true)
        sec:AddToggle("Adaptive Lighting", { Default = true, Bindable = false, Callback = function(value) engine.Options.adaptive = value end })
        sec:AddToggle("Screen Overlays", { Default = true, Bindable = false, Callback = function(value)
            engine.Options.overlays = value
            for _, object in pairs(engine.Overlays) do if object and object.Parent then object.Visible = value end end
        end })
        sec:AddToggle("Floating Dust", { Default = true, Bindable = false, Callback = function(value) engine.Options.particles = value end })
        sec:AddDropdown("Quality", { Options = { "Low", "Medium", "High" }, Default = "High", Callback = function(value)
            engine.Options.quality = value
            engine.Stats.quality = value
            if engine.Active then start(engine.Preset) end
        end })
        statsLabel = sec:AddLabel("Engine idle.", { Wrap = true, Color = Window.Theme.TextDim })
    end

    local api = {}
    function api.Open()
        Window:Toggle(true)
        Window:SelectTab(tab)
    end
    function api.Stop() stop() end
    function api.Destroy() stop() end
    function api.GetStats() return engine.Stats end
    function api.GetActive() return engine.Active end
    return api
end

return Shaders
