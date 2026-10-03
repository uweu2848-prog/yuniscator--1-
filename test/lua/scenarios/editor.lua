-- Exercise the free name-tag editor's curated presets, preview, reset, and export.
return function(H)
    H.runLoader()
    H.advance(3)

    local out = { hasPreviewHolder = #H.customFrames >= 2, hasFreeNameTagsTab = false, hasShadersTab = false, hasHomeTab = false, hasSettingsTab = false, hasPlayersTab = false, hasPlaylistTab = false, hasAboutTab = false, hasPlaceholderTabs = false }
    for _, name in ipairs(H.createdTabs or {}) do
        if name == "Home" then out.hasHomeTab = true end
        if name == "Players" then out.hasPlayersTab = true end
        if name == "Free Name Tags" then out.hasFreeNameTagsTab = true end
        if name == "Shaders" then out.hasShadersTab = true end
        if name == "Playlist" then out.hasPlaylistTab = true end
        if name == "About" then out.hasAboutTab = true end
        if name == "Settings" then out.hasSettingsTab = true end
        if name == "Player" or name == "Visuals" or name == "Misc" then out.hasPlaceholderTabs = true end
    end
    out.tabOrder = table.concat(H.createdTabs or {}, " > ")
    out.tabGroups = H.tabGroups or {}
    out.hasInfoBarShortcuts = H.infoBarOptions ~= nil
        and type(H.infoBarOptions.OnSettings) == "function"
        and type(H.infoBarOptions.OnGlobe) == "function"
        and type(H.infoBarOptions.OnNametag) == "function"
        and type(H.infoBarOptions.OnPlaylist) == "function"
        and type(H.infoBarOptions.OnDiscord) == "function"
    out.infoBarIdentity = H.infoBarOptions and H.infoBarOptions.Brand == "SCORP"
        and H.infoBarOptions.Channel == "PRODUCTION"
    out.hasStaffPanelButton = H.controls["Admin Panel · Staff"] ~= nil
    out.toggleKeyHasConfigFlag = H.controls["Menu Toggle Key"] and H.controls["Menu Toggle Key"].Flag == "menu_toggle_key"
    local function preview()
        H.advance(1) -- past the editor's 0.12 s debounce
        for _, holder in ipairs(H.customFrames) do
            local g = holder:FindFirstChild("ScorpTagPreview")
            if g then return H.summarize(g) end
        end
        return nil
    end
    local function ctl(name) return assert(H.controls[name], "missing control: " .. name) end

    out.initial = preview()
    out.hasImportControl = H.controls["Import Code"] ~= nil
    out.hasIndividualColorControl = H.controls.Primary ~= nil
    out.hasShaderProfiles = H.controls["Unreal Profile"] ~= nil
        and H.controls["Cinematic Profile"] ~= nil
        and H.controls["Bodycam Profile"] ~= nil
        and H.controls["Stop Engine / Restore"] ~= nil
    out.hasDashboardActions = H.controls["🏷️   Open Name Tag Studio"] ~= nil
        and H.controls["✨   Open Shader Studio"] ~= nil
        and H.controls["♫   Open Playlist"] ~= nil
        and H.controls["♙   Open Player List"] ~= nil
    local playlistFrame, playlistSearch
    for _, frame in ipairs(H.customFrames) do
        if H.find(frame, "ActionPlaylist") then playlistFrame = H.find(frame, "ActionPlaylist") end
        if H.find(frame, "PlaylistSearch") then playlistSearch = H.find(frame, "PlaylistSearch") end
    end
    out.hasPlaylistActions = H.controls.Category ~= nil
        and playlistFrame ~= nil
        and playlistSearch ~= nil
        and H.find(playlistFrame, "ActionRow_name-tags") ~= nil
        and H.find(playlistFrame, "Favorite") ~= nil
        and H.controls["Audio asset ID"] == nil

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
    out.hasFreeNameTagsShortcutInSettings = H.controls["Free Name Tags"] ~= nil

    H.window:Destroy()
    H.result(out)
end