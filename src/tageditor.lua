-- ───────────────────────────────────────────────────────────────────────────
--  Scorp tag editor
--
--  Pulled into src/script.lua by the build (--@include) and ends with
--  `return TagEditor`.  script.lua calls  TagEditor.Build(Window, Nametags).
--
--  Adds a "Tag Editor" tab: live preview, colour presets, text & fonts, images,
--  layout, all 29 colours, effects, text animation — and Export / Import.
--
--  Export makes a code like  SCORPTAG1.eyJ…  from everything that differs from the
--  defaults. Hand it to whoever runs your Discord bot: /tag import roblox_id code.
--  Import does the reverse: paste a code and every control jumps to it.
--
--  Everything the editor knows (options, defaults, fonts, presets, ranges) comes
--  from Nametags.TAGDATA, i.e. src/tagconfig.js — the same data the bot validates
--  against, so a code from here can't contain something the bot doesn't understand.
--
--  Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────

local TagEditor = {}

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

--- asset input → "rbxassetid://123" | "" | nil (invalid)
local function parseAsset(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = text:lower()
    if text == "" or low == "none" or low == "off" then return "" end
    local id = text:match("^rbxassetid://(%d+)$") or text:match("^(%d+)$") or text:match("/library/(%d+)") or text:match("/asset/(%d+)")
    if id then return "rbxassetid://" .. id end
    return nil
end

function TagEditor.Build(Window, Nametags)
    local DATA = Nametags.TAGDATA
    local D = DATA.defaults

    local COLOR_SET = {}
    for _, k in ipairs(DATA.colorKeys) do COLOR_SET[k] = true end

    local draft = {}      -- only the options that differ from the defaults (this is what gets exported)
    local controls = {}   -- option key → control, so an import / preset can move them
    local loading = false -- true while WE are pushing values into controls
    local worldPreview = false
    local previewHolder, previewFrame, previewTween, exportBox, exportLabel

    local function notify(text) Window:Notify("Tag Editor", text, 3) end

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    -- ── preview ──────────────────────────────────────────────────────────
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
        if worldPreview then Nametags.PreviewTag(draft) end
        updateExportViews()
    end

    local gen = 0
    local function scheduleRefresh()      -- sliders fire a lot; rebuild once they settle
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

    --- Push the draft into every control (import, preset, reset).
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

    -- ── tab ──────────────────────────────────────────────────────────────
    local tab = Window:CreateTab("Tag Editor", { Icon = "🎨" })

    -- Live preview
    do
        local sec = tab:CreateSection("Live Preview", true)
        previewHolder = sec:AddCustom(120)
        sec:AddToggle("Show On My Tag", {
            Default = false, Bindable = false,
            Callback = function(v)
                worldPreview = v and true or false
                Nametags.PreviewTag(worldPreview and draft or nil)
            end,
        })
        sec:AddButton("Reset Design", function()
            applyDraft({})
            notify("Design reset to the defaults.")
        end)
    end

    -- Presets
    do
        local sec = tab:CreateSection("Color Presets", true)
        local options = { "Choose a preset..." }
        for _, name in ipairs(DATA.presetOrder) do options[#options + 1] = name end
        controls._preset = nil
        sec:AddDropdown("Preset:", {
            Options = options, Default = options[1],
            Callback = function(v)
                local preset = DATA.colorPresets[v]
                if loading or not preset then return end
                for _, k in ipairs(DATA.colorKeys) do draft[k] = nil end   -- a preset replaces the whole palette
                for k, val in pairs(preset) do draft[k] = val end
                syncControls()
                notify(v .. " applied.")
            end,
        })
    end

    -- Text & Font
    do
        local sec = tab:CreateSection("Text & Font", true)
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
        controls.rankFont = sec:AddDropdown("Rank Font:", { Options = DATA.fonts, Default = D.rankFont, Callback = function(v) setKey("rankFont", v) end })
        controls.userFont = sec:AddDropdown("User Font:", { Options = DATA.fonts, Default = D.userFont, Callback = function(v) setKey("userFont", v) end })
        controls.textSize = sec:AddSlider("Text Size", { Min = DATA.ranges.textSize[1], Max = DATA.ranges.textSize[2], Default = D.textSize, Increment = 1, Callback = function(v) setKey("textSize", v) end })
    end

    -- Images
    do
        local sec = tab:CreateSection("Images", false)
        for _, def in ipairs({ { "image", "Logo Image", "asset id (empty = your avatar)" }, { "background", "Background Image", "asset id (empty = none)" } }) do
            local key = def[1]
            controls[key] = sec:AddTextbox(def[2], {
                Default = D[key], Placeholder = def[3],
                Callback = function(text)
                    local asset = parseAsset(text)
                    if asset == nil then
                        notify("That isn't an asset id. Use digits or rbxassetid://123456.")
                        revert(key)
                        return
                    end
                    setKey(key, asset)
                end,
            })
        end
    end

    -- Layout
    do
        local sec = tab:CreateSection("Layout", false)
        local R = DATA.ranges
        controls.fullWidth = sec:AddSlider("Card Width (0 = auto)", { Min = 0, Max = 300, Default = D.fullWidth, Increment = 2, Callback = function(v) setKey("fullWidth", v) end })
        controls.fullHeight = sec:AddSlider("Card Height", { Min = R.fullHeight[1], Max = R.fullHeight[2], Default = D.fullHeight, Increment = 1, Callback = function(v) setKey("fullHeight", v) end })
        controls.miniSize = sec:AddSlider("Mini Size", { Min = R.miniSize[1], Max = R.miniSize[2], Default = D.miniSize, Increment = 1, Callback = function(v) setKey("miniSize", v) end })
        controls.offsetFull = sec:AddSlider("Height Offset (full)", { Min = 0, Max = 8, Default = D.offsetFull, Increment = 0.05, Callback = function(v) setKey("offsetFull", v) end })
        controls.offsetMini = sec:AddSlider("Height Offset (mini)", { Min = 0, Max = 8, Default = D.offsetMini, Increment = 0.05, Callback = function(v) setKey("offsetMini", v) end })
        controls.distFull = sec:AddSlider("Full Card Until (studs)", { Min = 5, Max = 400, Default = D.distFull, Increment = 1, Callback = function(v) setKey("distFull", v) end })
        controls.distMini = sec:AddSlider("Logo Only From (studs)", { Min = 5, Max = 400, Default = D.distMini, Increment = 1, Callback = function(v) setKey("distMini", v) end })
        controls.distMax = sec:AddSlider("Hidden Beyond (studs)", { Min = 50, Max = 10000, Default = D.distMax, Increment = 50, Callback = function(v) setKey("distMax", v) end })
    end

    -- Colours (all 29)
    do
        local sec = tab:CreateSection("Colors", false)
        for _, key in ipairs(DATA.colorKeys) do
            controls[key] = sec:AddColorPicker(pretty(key), {
                Default = Nametags.Color(D[key]),
                Callback = function(c) setKey(key, Nametags.ColorToHex(c)) end,
            })
        end
    end

    -- Effects + animation
    do
        local sec = tab:CreateSection("Effects", false)
        for _, key in ipairs({ "glow", "pulse", "spin", "particles", "underlineSweep", "glitch", "effects", "grid", "logoMotion" }) do
            controls[key] = sec:AddToggle(pretty(key), {
                Default = D[key], Bindable = false,
                Callback = function(v) setKey(key, v and true or false) end,
            })
        end
    end
    do
        local sec = tab:CreateSection("Animation", false)
        controls.textAnimation = sec:AddDropdown("Text Animation:", { Options = DATA.animations, Default = D.textAnimation, Callback = function(v) setKey("textAnimation", v) end })
    end

    -- Export / Import
    do
        local sec = tab:CreateSection("Export / Import", true)
        exportLabel = sec:AddLabel("Nothing changed yet — edit something and the code appears here.", { Wrap = true })
        exportBox = sec:AddTextbox("Your Export Code", { Default = "", Placeholder = "(appears once you change something)", Callback = function() end })
        sec:AddButton("Copy Export Code", function()
            if countKeys(draft) == 0 then
                notify("Nothing to export yet — change something first.")
                return
            end
            local code = Nametags.Export(draft)
            if copyToClipboard(code) then
                notify("Export code copied (" .. #code .. " characters).")
            else
                print("[Scorp] tag export code:\n" .. code)
                notify("No clipboard access — the code was printed to the console (F9).")
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
    end

    rebuildPreview()

    local api = {}
    function api.GetDraft() return draft end
    function api.Export() return Nametags.Export(draft) end
    function api.Import(code)
        local options, err = Nametags.Import(code)
        if not options then return false, err end
        applyDraft(options)
        return true
    end
    --- Called when the UI unloads: stop the in-world preview and the preview's tween.
    function api.Destroy()
        if previewTween then pcall(function() previewTween:Cancel() end) previewTween = nil end
        Nametags.PreviewTag(nil)
    end
    return api
end

return TagEditor
