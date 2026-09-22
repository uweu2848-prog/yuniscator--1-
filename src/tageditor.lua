-- ───────────────────────────────────────────────────────────────────────────
--  Scorp tag editor  –  standalone floating window
--
--  TagEditor.Build(Scorp, Nametags) returns an api with:
--      api.Open()    – show the editor window
--      api.Close()   – hide it
--      api.Destroy() – clean up on unload
--      api.GetDraft(), api.Export(), api.Import(code)
--
--  Called from script.lua as:
--      local Editor = TagEditor.Build(Scorp, Nametags)
--      -- then in Settings:
--      sec:AddButton("Edit Nametag", function() Editor.Open() end)
--
--  Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────

local TagEditor = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function pretty(key)
    local s = key:gsub("(%l)(%u)", "%1 %2")
    s = s:gsub("^%l", string.upper)
    return s
end

local function copyToClipboard(text)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(fn) ~= "function" then return false end
    return (pcall(fn, text))
end

local function parseAsset(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = text:lower()
    if text == "" or low == "none" or low == "off" then return "" end
    local id = text:match("^rbxassetid://(%d+)$")
          or text:match("^(%d+)$")
          or text:match("/library/(%d+)")
          or text:match("/asset/(%d+)")
    if id then return "rbxassetid://" .. id end
    return nil
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ── standalone window builder ─────────────────────────────────────────────────

function TagEditor.Build(Scorp, Nametags)
    local DATA  = Nametags.TAGDATA
    local D     = DATA.defaults

    local COLOR_SET = {}
    for _, k in ipairs(DATA.colorKeys) do COLOR_SET[k] = true end

    local draft        = {}
    local controls     = {}
    local loading      = false
    local worldPreview = false
    local previewHolder, previewFrame, previewTween, exportBox, exportLabel

    -- ── the standalone window ──────────────────────────────────────────────
    --  CreateWindow accepts the same option table as the main window.
    --  We use a separate one so it floats independently (like MOIS7's editor).
    local EditorWindow = Scorp:CreateWindow({
        Title      = "M7 NAMETAG EDITOR",
        Subtitle   = "Design your tag",
        Theme      = "Dark",
        ToggleKey  = Enum.KeyCode.Unknown,   -- no auto-toggle; we control visibility
        ConfigFolder = "ScorpTagEditor",
        Starfield  = false,
        CloseButton = true,    -- X button in the top-right
        MinimizeButton = true, -- – button in the top-right bar
    })

    -- Hide on first build; shown when Editor.Open() is called.
    EditorWindow:SetVisible(false)

    local function notify(text) Scorp:Notify("Tag Editor", text, 3) end

    -- ── preview & export ──────────────────────────────────────────────────
    local function updateExportViews()
        if not exportLabel then return end
        local n = countKeys(draft)
        if n == 0 then
            exportLabel:Set("Nothing changed yet — edit something and the code appears here.")
            if exportBox then exportBox:Set("", true) end
            return
        end
        local code = Nametags.Export(draft)
        exportLabel:Set(n .. " option" .. (n == 1 and "" or "s") .. " changed  ·  code is " .. #code .. " characters")
        if exportBox then exportBox:Set(code, true) end
    end

    local function rebuildPreview()
        if previewFrame then pcall(function() previewFrame:Destroy() end) previewFrame = nil end
        if previewTween then pcall(function() previewTween:Cancel() end) previewTween = nil end
        if previewHolder then previewFrame, previewTween = Nametags.PreviewCard(previewHolder, draft) end
        if worldPreview  then Nametags.PreviewTag(draft) end
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

    local function setKey(key, value)
        if loading then return end
        if value == D[key] then draft[key] = nil else draft[key] = value end
        scheduleRefresh()
    end

    local function syncControls()
        loading = true
        for key, ctl in pairs(controls) do
            local v = draft[key]
            if v == nil then v = D[key] end
            pcall(function()
                if COLOR_SET[key] then ctl:Set(Nametags.Color(v), true) else ctl:Set(v, true) end
            end)
        end
        loading = false
        gen = gen + 1
        rebuildPreview()
    end

    local function applyDraft(newDraft)
        draft = {}
        for k, v in pairs(newDraft) do
            if v ~= D[k] then draft[k] = v end
        end
        syncControls()
    end

    local function revert(key)
        loading = true
        pcall(function() controls[key]:Set(draft[key] == nil and D[key] or draft[key], true) end)
        loading = false
    end

    -- ── tabs inside the editor window ─────────────────────────────────────

    -- Tab 1: Text & Font (most-used, shown first)
    local tabText = EditorWindow:CreateTab("Text & Font", { Icon = "🔤" })
    do
        -- Live Preview section at the very top of this tab
        local secPreview = tabText:CreateSection("LIVE PREVIEW", true)
        previewHolder = secPreview:AddCustom(120)
        secPreview:AddToggle("Show On My Tag", {
            Default = false, Bindable = false,
            Callback = function(v)
                worldPreview = v and true or false
                Nametags.PreviewTag(worldPreview and draft or nil)
            end,
        })
        secPreview:AddButton("Reset Design", function()
            applyDraft({})
            notify("Design reset to defaults.")
        end)

        local sec = tabText:CreateSection("TEXT & FONT", true)
        controls.label = sec:AddTextbox("Label Text", {
            Default = "", Placeholder = "(role name)",
            Callback = function(text)
                text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                setKey("label", text:sub(1, 24))
            end,
        })
        controls.userText = sec:AddTextbox("User Text", {
            Default = D.userText, Placeholder = "auto / none / your text",
            Callback = function(text)
                text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if text == "" then text = "auto" end
                if text:lower() == "auto" or text:lower() == "none" then text = text:lower() end
                setKey("userText", text:sub(1, 24))
            end,
        })
        controls.rankFont = sec:AddDropdown("Rank Font", {
            Options = DATA.fonts, Default = D.rankFont,
            Callback = function(v) setKey("rankFont", v) end,
        })
        controls.userFont = sec:AddDropdown("User Font", {
            Options = DATA.fonts, Default = D.userFont,
            Callback = function(v) setKey("userFont", v) end,
        })
        controls.textSize = sec:AddSlider("Text Size", {
            Min = DATA.ranges.textSize[1], Max = DATA.ranges.textSize[2],
            Default = D.textSize, Increment = 1,
            Callback = function(v) setKey("textSize", v) end,
        })

        -- Images sub-section
        local secImg = tabText:CreateSection("IMAGES", false)
        for _, def in ipairs({
            { "image",      "Logo Image",       "asset id (empty = your avatar)" },
            { "background", "Background Image",  "asset id (empty = none)"       },
        }) do
            local key = def[1]
            controls[key] = secImg:AddTextbox(def[2], {
                Default = D[key], Placeholder = def[3],
                Callback = function(text)
                    local asset = parseAsset(text)
                    if asset == nil then
                        notify("Invalid asset id — use digits or rbxassetid://123456.")
                        revert(key)
                        return
                    end
                    setKey(key, asset)
                end,
            })
        end
    end

    -- Tab 2: Colors & Effects
    local tabFX = EditorWindow:CreateTab("Colors & FX", { Icon = "🎨" })
    do
        -- Color presets
        local secPresets = tabFX:CreateSection("COLOR PRESETS", true)
        local presetOpts = { "Choose a preset..." }
        for _, name in ipairs(DATA.presetOrder) do presetOpts[#presetOpts + 1] = name end
        secPresets:AddDropdown("Preset", {
            Options = presetOpts, Default = presetOpts[1],
            Callback = function(v)
                local preset = DATA.colorPresets[v]
                if loading or not preset then return end
                for _, k in ipairs(DATA.colorKeys) do draft[k] = nil end
                for k, val in pairs(preset) do draft[k] = val end
                syncControls()
                notify(v .. " applied.")
            end,
        })

        -- All 29 colors
        local secColors = tabFX:CreateSection("COLORS", false)
        for _, key in ipairs(DATA.colorKeys) do
            controls[key] = secColors:AddColorPicker(pretty(key), {
                Default = Nametags.Color(D[key]),
                Callback = function(c) setKey(key, Nametags.ColorToHex(c)) end,
            })
        end

        -- Effects toggles
        local secFX = tabFX:CreateSection("EFFECTS", false)
        for _, key in ipairs({ "glow", "pulse", "spin", "particles", "underlineSweep", "glitch", "effects", "grid", "logoMotion" }) do
            controls[key] = secFX:AddToggle(pretty(key), {
                Default = D[key], Bindable = false,
                Callback = function(v) setKey(key, v and true or false) end,
            })
        end

        -- Text animation
        local secAnim = tabFX:CreateSection("ANIMATION", false)
        controls.textAnimation = secAnim:AddDropdown("Text Animation", {
            Options = DATA.animations, Default = D.textAnimation,
            Callback = function(v) setKey("textAnimation", v) end,
        })
    end

    -- Tab 3: Layout
    local tabLayout = EditorWindow:CreateTab("Layout", { Icon = "📐" })
    do
        local sec = tabLayout:CreateSection("LAYOUT", false)
        local R = DATA.ranges
        controls.fullWidth  = sec:AddSlider("Card Width (0 = auto)", { Min = 0, Max = 300, Default = D.fullWidth,  Increment = 2,    Callback = function(v) setKey("fullWidth",  v) end })
        controls.fullHeight = sec:AddSlider("Card Height",            { Min = R.fullHeight[1], Max = R.fullHeight[2], Default = D.fullHeight, Increment = 1, Callback = function(v) setKey("fullHeight", v) end })
        controls.miniSize   = sec:AddSlider("Mini Size",              { Min = R.miniSize[1],   Max = R.miniSize[2],   Default = D.miniSize,   Increment = 1, Callback = function(v) setKey("miniSize",   v) end })
        controls.offsetFull = sec:AddSlider("Height Offset (full)",   { Min = 0, Max = 8, Default = D.offsetFull, Increment = 0.05, Callback = function(v) setKey("offsetFull", v) end })
        controls.offsetMini = sec:AddSlider("Height Offset (mini)",   { Min = 0, Max = 8, Default = D.offsetMini, Increment = 0.05, Callback = function(v) setKey("offsetMini", v) end })
        controls.distFull   = sec:AddSlider("Full Card Until (studs)", { Min = 5, Max = 400, Default = D.distFull, Increment = 1, Callback = function(v) setKey("distFull", v) end })
        controls.distMini   = sec:AddSlider("Logo Only From (studs)",  { Min = 5, Max = 400, Default = D.distMini, Increment = 1, Callback = function(v) setKey("distMini", v) end })
        controls.distMax    = sec:AddSlider("Hidden Beyond (studs)",   { Min = 50, Max = 10000, Default = D.distMax, Increment = 50, Callback = function(v) setKey("distMax", v) end })
    end

    -- Tab 4: Export / Import
    local tabExport = EditorWindow:CreateTab("Export / Import", { Icon = "💾" })
    do
        local sec = tabExport:CreateSection("EXPORT / IMPORT", true)
        exportLabel = sec:AddLabel("Nothing changed yet — edit something and the code appears here.", { Wrap = true })
        exportBox   = sec:AddTextbox("Your Export Code", { Default = "", Placeholder = "(appears once you change something)", Callback = function() end })
        sec:AddButton("Copy Export Code", function()
            if countKeys(draft) == 0 then
                notify("Nothing to export yet — change something first.")
                return
            end
            local code = Nametags.Export(draft)
            if copyToClipboard(code) then
                notify("Copied (" .. #code .. " chars).")
            else
                print("[Scorp] tag export code:\n" .. code)
                notify("No clipboard access — code printed to F9 console.")
            end
        end)
        sec:AddTextbox("Import Code", {
            Default = "", Placeholder = "paste a SCORPTAG1.… code and press Enter",
            Callback = function(text)
                if tostring(text or ""):gsub("%s", "") == "" then return end
                local options, err = Nametags.Import(text)
                if not options then
                    notify("Import failed: " .. tostring(err))
                    return
                end
                applyDraft(options)
                notify("Imported " .. countKeys(draft) .. " option(s).")
            end,
        })
        sec:AddButton("Reset to Defaults", function()
            applyDraft({})
            notify("Design reset to defaults.")
        end)
    end

    -- Initial preview build
    rebuildPreview()

    -- ── public API ────────────────────────────────────────────────────────
    local api = {}

    function api.Open()
        EditorWindow:SetVisible(true)
    end

    function api.Close()
        EditorWindow:SetVisible(false)
    end

    function api.GetDraft() return draft end

    function api.Export() return Nametags.Export(draft) end

    function api.Import(code)
        local options, err = Nametags.Import(code)
        if not options then return false, err end
        applyDraft(options)
        return true
    end

    function api.Destroy()
        if previewTween then pcall(function() previewTween:Cancel() end) previewTween = nil end
        Nametags.PreviewTag(nil)
        pcall(function() EditorWindow:Destroy(true) end)
    end

    return api
end

return TagEditor