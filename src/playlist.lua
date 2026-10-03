-- Yuniku-inspired command playlist: searchable actions grouped by category,
-- with a persistent Favorites section. Actions are Scorp features only; this
-- deliberately does not execute arbitrary strings or third-party commands.
local Playlist = {}

local ACTIONS = {
    { id = "name-tags", name = "Name Tag Studio", description = "Choose a curated name-tag design.", category = "Studio" },
    { id = "shaders", name = "Shader Studio", description = "Open local visual profiles and controls.", category = "Studio" },
    { id = "shader-stop", name = "Stop Visual Engine", description = "Remove the active Scorp visual profile.", category = "Studio" },
    { id = "players", name = "Current Server Roster", description = "View players in this server.", category = "Workspace" },
    { id = "refresh-tags", name = "Refresh Nametags", description = "Request the latest server-authorized tags.", category = "Identity" },
    { id = "preview-vip", name = "Preview VIP Tag", description = "Show a local-only VIP nametag preview.", category = "Identity" },
    { id = "clear-preview", name = "Clear Tag Preview", description = "Restore your normal nametag preview.", category = "Identity" },
    { id = "settings", name = "Appearance & Settings", description = "Change Scorp theme and client preferences.", category = "Preferences" },
    { id = "about", name = "About Scorp", description = "View release and community information.", category = "Preferences" },
}

function Playlist.Build(Window, actions)
    actions = actions or {}
    local HttpService = game:GetService("HttpService")
    local tab = Window:CreateTab("Player List", { Icon = "♫", Group = "Studio" })
    local favoriteFile = "Scorp/playlist-favorites.json"
    local favorites = {}
    local category = "All"
    local query = ""
    local rows = {}
    local rowStyles = {}
    local favoritesCount
    local emptyLabel
    local actionList

    local function loadFavorites()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        local ok, exists = pcall(isfile, favoriteFile)
        if not ok or not exists then return end
        local readOk, raw = pcall(readfile, favoriteFile)
        if not readOk or type(raw) ~= "string" then return end
        local decodeOk, saved = pcall(function() return HttpService:JSONDecode(raw) end)
        if decodeOk and type(saved) == "table" then
            for _, id in ipairs(saved) do if type(id) == "string" then favorites[id] = true end end
        end
    end

    local function saveFavorites()
        if type(writefile) ~= "function" then return false end
        local saved = {}
        for id, active in pairs(favorites) do if active then saved[#saved + 1] = id end end
        table.sort(saved)
        pcall(function()
            if type(isfolder) == "function" and type(makefolder) == "function" then
                if not isfolder("Scorp") then makefolder("Scorp") end
            end
        end)
        return pcall(writefile, favoriteFile, HttpService:JSONEncode(saved))
    end

    local function notify(text, bad)
        Window:Notify("Player List", text, 3, bad and Window.Theme.Warning or Window.Theme.Success)
    end

    local function visibleActions()
        local result = {}
        local needle = query:lower()
        for _, action in ipairs(ACTIONS) do
            local categoryMatches = category == "All" or action.category == category
            local text = (action.name .. " " .. action.description .. " " .. action.category):lower()
            if categoryMatches and (needle == "" or text:find(needle, 1, true)) then
                result[#result + 1] = action
            end
        end
        table.sort(result, function(a, b)
            if favorites[a.id] ~= favorites[b.id] then return favorites[a.id] == true end
            return a.name:lower() < b.name:lower()
        end)
        return result
    end

    local function run(action)
        local callback = actions[action.id]
        if type(callback) ~= "function" then
            notify(action.name .. " is not available in this session.", true)
            return
        end
        local ok, err = pcall(callback)
        if not ok then
            warn("[Scorp Playlist] " .. action.id .. " failed: " .. tostring(err))
            notify("Could not run " .. action.name .. ".", true)
        end
    end

    local function clearRows()
        for _, row in ipairs(rows) do pcall(function() row:Destroy() end) end
        rows = {}
        rowStyles = {}
    end

    local function render()
        clearRows()
        local list = visibleActions()
        favoritesCount = 0
        for _, action in ipairs(list) do if favorites[action.id] then favoritesCount = favoritesCount + 1 end end
        emptyLabel.Visible = #list == 0
        for order, action in ipairs(list) do
            local card = Instance.new("Frame")
            card.Name = "ActionRow_" .. action.id
            card.Size = UDim2.new(1, -6, 0, 56)
            card.BackgroundColor3 = Window.Theme.ToggleOff
            card.BackgroundTransparency = 0.2
            card.BorderSizePixel = 0
            card.LayoutOrder = order + (favoritesCount > 0 and 1 or 0)
            card.Parent = actionList
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 9)
            corner.Parent = card
            local outline = Instance.new("UIStroke")
            outline.Color = Window.Theme.Accent
            outline.Transparency = 0.78
            outline.Thickness = 1
            outline.Parent = card

            local launch = Instance.new("TextButton")
            launch.Name = "LaunchAction"
            launch.Size = UDim2.new(1, -48, 1, 0)
            launch.BackgroundTransparency = 1
            launch.Text = ""
            launch.AutoButtonColor = false
            launch.Parent = card

            local title = Instance.new("TextLabel")
            title.BackgroundTransparency = 1
            title.Position = UDim2.fromOffset(12, 8)
            title.Size = UDim2.new(1, -20, 0, 18)
            title.Font = Enum.Font.GothamBold
            title.Text = action.name
            title.TextColor3 = Window.Theme.TextWhite
            title.TextSize = 12
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.TextTruncate = Enum.TextTruncate.AtEnd
            title.Parent = launch

            local description = Instance.new("TextLabel")
            description.BackgroundTransparency = 1
            description.Position = UDim2.fromOffset(12, 29)
            description.Size = UDim2.new(1, -20, 0, 17)
            description.Font = Enum.Font.Gotham
            description.Text = action.description
            description.TextColor3 = Window.Theme.TextDim
            description.TextSize = 10
            description.TextXAlignment = Enum.TextXAlignment.Left
            description.TextTruncate = Enum.TextTruncate.AtEnd
            description.Parent = launch

            local star = Instance.new("TextButton")
            star.Name = "Favorite"
            star.Size = UDim2.fromOffset(38, 42)
            star.Position = UDim2.new(1, -42, 0.5, -21)
            star.BackgroundTransparency = 1
            star.Text = favorites[action.id] and "★" or "☆"
            star.TextColor3 = favorites[action.id] and Window.Theme.AccentLight or Window.Theme.TextDim
            star.TextSize = 19
            star.Font = Enum.Font.GothamBold
            star.AutoButtonColor = false
            star.Parent = card

            launch.MouseEnter:Connect(function()
                card.BackgroundTransparency = 0.05
                outline.Transparency = 0.42
            end)
            launch.MouseLeave:Connect(function()
                card.BackgroundTransparency = 0.2
                outline.Transparency = 0.78
            end)
            launch.MouseButton1Click:Connect(function() run(action) end)
            star.MouseButton1Click:Connect(function()
                favorites[action.id] = not favorites[action.id] and true or nil
                local saved = saveFavorites()
                render()
                local message = favorites[action.id] and "Added to favorites." or "Removed from favorites."
                if saved then message = message .. " Saved on this device." else message = message .. " Session only · executor file storage is unavailable." end
                notify(message)
            end)
            rows[#rows + 1] = card
            rowStyles[#rowStyles + 1] = { card = card, outline = outline }
        end
        if favoritesCount > 0 then
            local header = Instance.new("TextLabel")
            header.Name = "FavoritesHeader"
            header.Size = UDim2.new(1, -6, 0, 20)
            header.BackgroundTransparency = 1
            header.LayoutOrder = 1
            header.Text = "★  FAVORITES"
            header.TextColor3 = Window.Theme.AccentLight
            header.Font = Enum.Font.GothamBold
            header.TextSize = 10
            header.TextXAlignment = Enum.TextXAlignment.Left
            header.Parent = actionList
            table.insert(rows, 1, header)
        end
        if favoritesCount == 0 then
            favoritesCount = 0
        end
    end

    do
        local section = tab:CreateSection("SCORP ACTIONS", true)
        section:AddLabel("Build a personal favorites list from Scorp's built-in tools. Search or filter, then select a row to open or run it.", { Wrap = true, Color = Window.Theme.TextDim })
        section:AddDropdown("Category", { Options = { "All", "Studio", "Workspace", "Identity", "Preferences" }, Default = "All", Callback = function(value)
            category = value
            render()
        end })
        local searchRow = section:AddCustom(34)
        local searchBox = Instance.new("TextBox")
        searchBox.Name = "PlaylistSearch"
        searchBox.Size = UDim2.new(1, 0, 1, 0)
        searchBox.BackgroundColor3 = Window.Theme.ToggleOff
        searchBox.BackgroundTransparency = 0.15
        searchBox.BorderSizePixel = 0
        searchBox.ClearTextOnFocus = false
        searchBox.PlaceholderText = "Search actions and descriptions..."
        searchBox.PlaceholderColor3 = Window.Theme.TextDim
        searchBox.Text = ""
        searchBox.TextColor3 = Window.Theme.TextWhite
        searchBox.TextSize = 12
        searchBox.Font = Enum.Font.Gotham
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.Parent = searchRow
        local searchCorner = Instance.new("UICorner")
        searchCorner.CornerRadius = UDim.new(0, 8)
        searchCorner.Parent = searchBox
        local searchPadding = Instance.new("UIPadding")
        searchPadding.PaddingLeft = UDim.new(0, 10)
        searchPadding.PaddingRight = UDim.new(0, 10)
        searchPadding.Parent = searchBox
        Window:_bind(function(theme) searchBox.BackgroundColor3 = theme.ToggleOff end)
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            query = searchBox.Text
            render()
        end)
        actionList = section:AddCustom(310)
        actionList.ClipsDescendants = true
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "ActionPlaylist"
        scroll.Size = UDim2.fromScale(1, 1)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 3
        scroll.ScrollBarImageColor3 = Window.Theme.Accent
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new()
        scroll.Parent = actionList
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.Parent = scroll
        Window:_bind(function(theme) scroll.ScrollBarImageColor3 = theme.Accent end)
        actionList = scroll
        emptyLabel = Instance.new("TextLabel")
        emptyLabel.Name = "PlaylistEmpty"
        emptyLabel.Size = UDim2.new(1, -16, 0, 52)
        emptyLabel.Position = UDim2.fromOffset(8, 12)
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.Text = "No actions match this filter.\nTry another search or category."
        emptyLabel.TextColor3 = Window.Theme.TextDim
        emptyLabel.TextSize = 11
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextWrapped = true
        emptyLabel.Visible = false
        emptyLabel.Parent = scroll
    end

    loadFavorites()
    render()

    local api = {}
    function api.Open()
        Window:Toggle(true)
        Window:SelectTab(tab)
    end
    function api.Destroy() clearRows() end
    function api.GetFavorites()
        local result = {}
        for id, active in pairs(favorites) do if active then result[#result + 1] = id end end
        table.sort(result)
        return result
    end
    return api
end

return Playlist
