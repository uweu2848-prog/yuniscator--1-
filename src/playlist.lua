-- Local, user-managed Roblox audio playlist. Playback is client-side and only
-- works for assets the current experience/account is allowed to load.
local Playlist = {}

function Playlist.Build(Window)
    local SoundService = game:GetService("SoundService")
    local tab = Window:CreateTab("Playlist", { Icon = "♫", Group = "Studio" })
    local tracks = {}
    local selectedIndex = nil
    local loopTrack = false
    local sound = Instance.new("Sound")
    sound.Name = "ScorpPlaylistPlayer"
    sound.Volume = 0.5
    sound.Parent = SoundService

    local statusLabel
    local trackPicker
    local trackChoices = {}

    local function setStatus(text)
        if statusLabel then statusLabel:Set(text) end
    end

    local function makeChoices()
        local options = {}
        trackChoices = {}
        for index, track in ipairs(tracks) do
            local label = string.format("%02d  ·  %s", index, track.name)
            options[#options + 1] = label
            trackChoices[label] = index
        end
        trackPicker:Refresh(options, false)
    end

    local function stop()
        pcall(function() sound:Stop() end)
        setStatus("Playback stopped.")
    end

    local function playAt(index)
        if #tracks == 0 then setStatus("Add an audio asset ID to start a playlist."); return false end
        if index < 1 then index = #tracks elseif index > #tracks then index = 1 end
        selectedIndex = index
        local track = tracks[selectedIndex]
        sound:Stop()
        sound.SoundId = "rbxassetid://" .. track.id
        local ok, err = pcall(function() sound:Play() end)
        if not ok then
            setStatus("Could not play this audio asset · check experience permissions.")
            warn("[Scorp Playlist] playback failed: " .. tostring(err))
            return false
        end
        trackPicker:Set(trackChoices[string.format("%02d  ·  %s", selectedIndex, track.name)], true)
        setStatus("Now playing · " .. track.name)
        return true
    end

    local function addTrack(idText, nameText)
        local id = tostring(idText or ""):gsub("%s", "")
        local name = tostring(nameText or ""):gsub("^%s*(.-)%s*$", "%1")
        if id:match("^rbxassetid://") then id = id:gsub("^rbxassetid://", "") end
        if not id:match("^%d+$") then setStatus("Enter a numeric Roblox audio asset ID."); return end
        if #tracks >= 40 then setStatus("Playlist limit reached · remove a track before adding more."); return end
        for _, track in ipairs(tracks) do
            if track.id == id then setStatus("That audio asset is already in this playlist."); return end
        end
        if name == "" then name = "Audio " .. id end
        tracks[#tracks + 1] = { id = id, name = name:sub(1, 48) }
        makeChoices()
        if not selectedIndex then
            selectedIndex = 1
            trackPicker:Set(trackChoices[1], true)
        end
        setStatus("Added · " .. tracks[#tracks].name .. "  (" .. tostring(#tracks) .. " tracks)")
    end

    local function removeSelected()
        if not selectedIndex or not tracks[selectedIndex] then setStatus("Choose a track to remove."); return end
        local wasPlaying = sound.IsPlaying
        table.remove(tracks, selectedIndex)
        sound:Stop()
        if #tracks == 0 then
            selectedIndex = nil
            trackPicker:Set(nil, true)
        else
            if selectedIndex > #tracks then selectedIndex = #tracks end
            makeChoices()
            trackPicker:Set(trackChoices[string.format("%02d  ·  %s", selectedIndex, tracks[selectedIndex].name)], true)
            if wasPlaying then playAt(selectedIndex) end
        end
        makeChoices()
        setStatus("Track removed · " .. tostring(#tracks) .. " remaining.")
    end

    do
        local section = tab:CreateSection("NOW PLAYING", true)
        section:AddLabel("A private local playlist. Roblox may restrict audio assets that are not permitted in this experience.", { Wrap = true, Color = Window.Theme.TextDim })
        statusLabel = section:AddLabel("Add an audio asset ID to start a playlist.", { Wrap = true })
        trackPicker = section:AddDropdown("Track", { Options = {}, Callback = function(choice)
            selectedIndex = trackChoices[choice]
        end })
        section:AddButton("▶   Play / Resume", function()
            if sound.IsPlaying then
                sound:Pause()
                setStatus("Paused · " .. (tracks[selectedIndex] and tracks[selectedIndex].name or "playlist"))
            elseif selectedIndex then
                if sound.SoundId == "rbxassetid://" .. tracks[selectedIndex].id then
                    sound:Resume()
                    setStatus("Now playing · " .. tracks[selectedIndex].name)
                else
                    playAt(selectedIndex)
                end
            else
                playAt(1)
            end
        end)
        section:AddButton("■   Stop Playback", stop)
        section:AddButton("◀   Previous Track", function() if selectedIndex then playAt(selectedIndex - 1) else playAt(1) end end)
        section:AddButton("▶   Next Track", function() if selectedIndex then playAt(selectedIndex + 1) else playAt(1) end end)
        section:AddToggle("Repeat Current Track", { Default = false, Bindable = false, Callback = function(value) loopTrack = value end })
        section:AddSlider("Volume", { Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%", Bindable = false, Callback = function(value) sound.Volume = value / 100 end })
    end

    do
        local section = tab:CreateSection("PLAYLIST", true)
        local nameBox = section:AddTextbox("Track name", { Default = "", Placeholder = "Optional display name" })
        local idBox = section:AddTextbox("Audio asset ID", { Default = "", Placeholder = "Numeric ID or rbxassetid://…" })
        section:AddButton("＋   Add Track", function()
            addTrack(idBox:Get(), nameBox:Get())
            if selectedIndex then
                idBox:Set("", true)
                nameBox:Set("", true)
            end
        end)
        section:AddButton("−   Remove Selected Track", removeSelected)
        section:AddLabel("Tracks are kept for this session only. Use audio you own or have permission to play.", { Wrap = true, Color = Window.Theme.TextDim })
    end

    sound.Ended:Connect(function()
        if loopTrack and selectedIndex then
            playAt(selectedIndex)
        elseif selectedIndex and selectedIndex < #tracks then
            playAt(selectedIndex + 1)
        else
            setStatus("Playlist finished.")
        end
    end)

    local api = {}
    function api.Open()
        Window:Toggle(true)
        Window:SelectTab(tab)
    end
    function api.Stop() stop() end
    function api.Destroy()
        stop()
        pcall(function() sound:Destroy() end)
    end
    function api.GetTracks() return tracks end
    return api
end

return Playlist
