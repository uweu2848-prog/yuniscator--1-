-- Exercise the free name-tag editor's curated presets, preview, reset, and export.
return function(H)
    H.runLoader()
    H.advance(3)

    local out = { hasPreviewHolder = #H.customFrames >= 1 }
    local holder = H.customFrames[1]
    local function preview()
        H.advance(1) -- past the editor's 0.12 s debounce
        local g = holder and holder:FindFirstChild("ScorpTagPreview")
        return g and H.summarize(g) or nil
    end
    local function ctl(name) return assert(H.controls[name], "missing control: " .. name) end

    out.initial = preview()
    out.hasImportControl = H.controls["Import Code"] ~= nil
    out.hasIndividualColorControl = H.controls.Primary ~= nil

    ctl("Color Theme:").Callback("Cyber Blue")
    ctl("Font Style:").Callback("Sci-Fi")
    ctl("Effect Pack:").Callback("Rainbow Fade")
    out.rainbow = preview()
    H.controls["Copy Free Design Code"].Callback()
    out.rainbowCode = H.clipboard

    ctl("Effect Pack:").Callback("Glitch Pop")
    out.glitch = preview()
    H.controls["Copy Free Design Code"].Callback()
    out.glitchCode = H.clipboard

    H.controls["Reset Free Design"].Callback()
    out.afterReset = preview()
    out.resetFontStyle = H.controlObjs["Font Style:"].value
    out.resetEffectPack = H.controlObjs["Effect Pack:"].value
    H.controls["Free Name Tags"].Callback()
    out.popoutTitle = H.popoutTitle
    out.popoutOpened = H.popoutShown

    H.window:Destroy()
    H.result(out)
end