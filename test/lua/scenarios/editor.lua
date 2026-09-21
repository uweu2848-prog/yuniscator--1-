-- Drive the tag editor like a person would: change controls, read the live preview,
-- copy the export code, then import a code that was made by the JS side.
-- Reports everything as JSON so test/run.js can check both directions of the format.
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
    out.controlCount = (function() local n = 0 for _ in pairs(H.controls) do n = n + 1 end return n end)()

    -- edit a bunch of controls
    ctl("Label Text").Callback("Cosmic Herald")
    ctl("User Text").Callback("none")
    ctl("Rank Font:").Callback("GothamBlack")
    ctl("Text Size").Callback(18)
    ctl("Primary").Callback({ R = 1, G = 136 / 255, B = 0 })
    ctl("Glow").Callback(false)
    ctl("Particles").Callback(true)
    ctl("Text Animation:").Callback("wave")
    ctl("Logo Image").Callback("1270554045585765")
    ctl("Card Width (0 = auto)").Callback(168)
    ctl("Card Height").Callback(34)
    out.edited = preview()

    -- a bad asset id is refused and the control snaps back
    ctl("Logo Image").Callback("not an id")
    H.advance(1)
    out.logoAfterBad = H.controlObjs["Logo Image"].value

    -- export
    H.controls["Copy Export Code"].Callback()
    out.code = H.clipboard
    out.exportBoxValue = H.controlObjs["Your Export Code"].value

    -- reset, then import a code made elsewhere (env IMPORT_CODE)
    H.controls["Reset Design"].Callback()
    out.afterReset = preview()
    local imported = os.getenv("IMPORT_CODE")
    if imported and imported ~= "" then
        ctl("Import Code").Callback(imported)
        out.imported = preview()
        out.importedControls = {
            textSize = H.controlObjs["Text Size"].value,
            rankFont = H.controlObjs["Rank Font:"].value,
            glow = H.controlObjs["Glow"].value,
            primary = H.controlObjs["Primary"].value and { H.controlObjs["Primary"].value.R, H.controlObjs["Primary"].value.G, H.controlObjs["Primary"].value.B },
            label = H.controlObjs["Label Text"].value,
            userText = H.controlObjs["User Text"].value,
        }
        H.controls["Copy Export Code"].Callback()
        out.reexported = H.clipboard
    end

    -- garbage codes are rejected with a reason and change nothing
    local before = H.notifies and #H.notifies or 0
    ctl("Import Code").Callback("SCORPTAG1.abc.00000000")
    ctl("Import Code").Callback("hello")
    out.rejects = {}
    for i = before + 1, #H.notifies do out.rejects[#out.rejects + 1] = H.notifies[i] end

    H.window:Destroy()
    H.result(out)
end
