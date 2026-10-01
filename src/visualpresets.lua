-- Safe, local-only appearance presets. This module adds only its own
-- post-processing instances and removes them on reset/unload; it does not
-- rewrite the game's lighting, materials, camera, or other players.
local VisualPresets = {}
local Lighting = game:GetService("Lighting")
local activeEffects = {}

local PRESETS = {
    ["Cinematic"] = {
        tint = Color3.fromRGB(255, 244, 232), brightness = -0.02, contrast = 0.12, saturation = -0.08,
        bloom = 0.12, threshold = 1.15,
    },
    ["Warm Sunset"] = {
        tint = Color3.fromRGB(255, 225, 195), brightness = 0.015, contrast = 0.06, saturation = 0.08,
        bloom = 0.2, threshold = 1.1,
    },
    ["Noir"] = {
        tint = Color3.fromRGB(224, 228, 245), brightness = -0.015, contrast = 0.18, saturation = -0.8,
        bloom = 0.08, threshold = 1.25,
    },
    ["Neon Pop"] = {
        tint = Color3.fromRGB(232, 244, 255), brightness = 0.02, contrast = 0.12, saturation = 0.22,
        bloom = 0.24, threshold = 0.95,
    },
}

function VisualPresets.Stop()
    for i = #activeEffects, 1, -1 do
        local effect = activeEffects[i]
        if effect and effect.Parent then pcall(function() effect:Destroy() end) end
        activeEffects[i] = nil
    end
end

function VisualPresets.List()
    local names = { "Off" }
    for name in pairs(PRESETS) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == "Off" then return true end
        if b == "Off" then return false end
        return a < b
    end)
    return names
end

function VisualPresets.Apply(name)
    VisualPresets.Stop()
    if name == nil or name == "Off" then return true end
    local preset = PRESETS[name]
    if not preset then return false, "Unknown visual preset." end

    local color = Instance.new("ColorCorrectionEffect")
    color.Name = "ScorpLocalColorGrade"
    color.TintColor = preset.tint
    color.Brightness = preset.brightness
    color.Contrast = preset.contrast
    color.Saturation = preset.saturation
    color.Parent = Lighting
    activeEffects[#activeEffects + 1] = color

    local bloom = Instance.new("BloomEffect")
    bloom.Name = "ScorpLocalBloom"
    bloom.Intensity = preset.bloom
    bloom.Threshold = preset.threshold
    bloom.Size = 18
    bloom.Parent = Lighting
    activeEffects[#activeEffects + 1] = bloom
    return true
end

return VisualPresets
