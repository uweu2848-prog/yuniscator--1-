-- ───────────────────────────────────────────────────────────────────────────
--  Scorp free name-tag presets
--
--  Pulled into src/script.lua by the build (--@include) and ends with
--  `return TagEditor`. The free editor intentionally offers curated font,
--  color and effect presets; detailed customization remains outside this UI.
--  All preset data comes from src/tagconfig.js via Nametags.TAGDATA.
--
--  Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────

local TagEditor = {}

local function copyToClipboard(text)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(fn) ~= "function" then return false end
    return (pcall(fn, text))
end

function TagEditor.Build(Window, Nametags)
    local DATA = Nametags.TAGDATA
    local D = DATA.defaults
    local function notify(text) Window:Notify("Free Name Tags", text, 3) end

    local draft = {}
    local controls = {}
    local loading = false
    local worldPreview = false
    local previewHolder, effectPreviewHolder, previewFrame, previewTween, effectPreviewFrame, effectPreviewTween, exportLabel

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    local function updateExportViews()
        if not exportLabel then return end
        local n = countKeys(draft)
        if n == 0 then
            exportLabel:Set("Choose a preset to create a free name-tag design code.")
            return
        end
        exportLabel:Set(n .. " preset option" .. (n == 1 and "" or "s") .. " selected · share the code with staff to apply it to your account.")
    end

    local function rebuildPreview()
        if previewFrame then pcall(function() previewFrame:Destroy() end) previewFrame = nil end
        if previewTween then pcall(function() previewTween:Cancel() end) previewTween = nil end
        if effectPreviewFrame then pcall(function() effectPreviewFrame:Destroy() end) effectPreviewFrame = nil end
        if effectPreviewTween then pcall(function() effectPreviewTween:Cancel() end) effectPreviewTween = nil end
        if previewHolder then previewFrame, previewTween = Nametags.PreviewCard(previewHolder, draft) end
        if effectPreviewHolder then effectPreviewFrame, effectPreviewTween = Nametags.PreviewCard(effectPreviewHolder, draft) end
        if worldPreview then Nametags.PreviewTag(draft) end
        updateExportViews()
    end

    local gen = 0
    local function scheduleRefresh()
        gen = gen + 1
        local mine = gen
        task.delay(0.12, function()
            if mine == gen then rebuildPreview() end
        end)
    end

    local function applyPreset(keys, preset)
        if loading or not preset then return end
        for _, key in ipairs(keys) do draft[key] = nil end
        for key, value in pairs(preset) do
            if value ~= D[key] then draft[key] = value end
        end
        scheduleRefresh()
    end

    local function resetDesign()
        draft = {}
        loading = true
        if controls.color then controls.color:Set("Silver Surfer", true) end
        if controls.font then controls.font:Set("Classic", true) end
        if controls.effect then controls.effect:Set("Classic Glow", true) end
        loading = false
        gen = gen + 1
        rebuildPreview()
    end

    local tab = Window:CreateTab("Free Name Tags", { Icon = "🏷️" })
    local effectTab = Window:CreateTab("Tag Effects", { Icon = "✨" })

    do
        local sec = tab:CreateSection("Free Name Tags", true)
        sec:AddLabel("Make your tag stand out with ready-made fonts, color palettes, and animated effect packs.", { Wrap = true })
        previewHolder = sec:AddCustom(120)
        sec:AddToggle("Preview On My Tag", {
            Default = false, Bindable = false,
            Callback = function(v)
                worldPreview = v and true or false
                Nametags.PreviewTag(worldPreview and draft or nil)
            end,
        })
        sec:AddButton("Reset Free Design", resetDesign)
    end

    do
        local sec = tab:CreateSection("Color Themes", true)
        sec:AddLabel("Pick a complete premade palette. Individual color editing is not part of the free tier.", { Wrap = true })
        local options = {}
        for _, name in ipairs(DATA.presetOrder) do options[#options + 1] = name end
        controls.color = sec:AddDropdown("Color Theme:", {
            Options = options, Default = "Silver Surfer",
            Callback = function(name)
                if loading then return end
                applyPreset(DATA.colorKeys, DATA.colorPresets[name])
                notify(name .. " color theme selected.")
            end,
        })
    end

    do
        local sec = tab:CreateSection("Font Styles", true)
        sec:AddLabel("Each style pairs a title font with a matching name font.", { Wrap = true })
        local options = {}
        for _, name in ipairs(DATA.freeFontPresetOrder) do options[#options + 1] = name end
        controls.font = sec:AddDropdown("Font Style:", {
            Options = options, Default = "Classic",
            Callback = function(name)
                if loading then return end
                applyPreset({ "rankFont", "userFont" }, DATA.freeFontPresets[name])
                notify(name .. " font style selected.")
            end,
        })
    end

    do
        local sec = tab:CreateSection("Premium Name Tags · Planned", false)
        sec:AddLabel("A future paid tier is planned for deeper customization, such as custom colors, expanded font choices, images, layout controls, and individual effect tuning. The free preset packs will remain available.", { Wrap = true, Color = Window.Theme.TextDim })
    end

    do
        local sec = tab:CreateSection("Share Free Design", false)
        exportLabel = sec:AddLabel("Choose a preset to create a free name-tag design code.", { Wrap = true })
        sec:AddButton("Copy Free Design Code", function()
            if countKeys(draft) == 0 then
                notify("Choose a preset first.")
                return
            end
            local code = Nametags.Export(draft)
            if copyToClipboard(code) then
                notify("Free design code copied.")
            else
                print("[Scorp] free tag code:\n" .. code)
                notify("No clipboard access — the code was printed to the console (F9).")
            end
        end)
    end

    do
        local sec = effectTab:CreateSection("Effect Packs", true)
        sec:AddLabel("Choose a ready-made animation pack. Each pack replaces the previous one, so effects won't stack or fight each other.", { Wrap = true })
        effectPreviewHolder = sec:AddCustom(110)
        local options = {}
        for _, name in ipairs(DATA.freeEffectPresetOrder) do options[#options + 1] = name end
        controls.effect = sec:AddDropdown("Effect Pack:", {
            Options = options, Default = "Classic Glow",
            Callback = function(name)
                if loading then return end
                applyPreset({ "textAnimation", "effects", "glow", "pulse", "spin", "particles", "underlineSweep", "glitch", "grid", "logoMotion" }, DATA.freeEffectPresets[name])
                notify(name .. " effect pack selected.")
            end,
        })
    end

    rebuildPreview()

    local api = {}
    function api.Open()
        Window:Toggle(true)
        Window:SelectTab(tab)
    end
    function api.GetDraft() return draft end
    function api.Export() return Nametags.Export(draft) end
    function api.Destroy()
        if previewTween then pcall(function() previewTween:Cancel() end) previewTween = nil end
        if effectPreviewTween then pcall(function() effectPreviewTween:Cancel() end) effectPreviewTween = nil end
        -- This tab belongs to the main window; cleanup only its preview and draft overlay.
        Nametags.PreviewTag(nil)
    end
    return api
end

return TagEditor