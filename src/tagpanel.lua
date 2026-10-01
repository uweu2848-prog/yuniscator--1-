-- ───────────────────────────────────────────────────────────────────────────
-- Tag-manager console. This module deliberately contains no moderation actions.
-- Server endpoints independently restrict tag managers to Member/VIP tags.
-- Lua 5.1 syntax only.
-- ───────────────────────────────────────────────────────────────────────────
local TagPanel = {}

function TagPanel.Build(Window, ctx)
    local HttpService = game:GetService("HttpService")
    local panel = Window:CreatePopout({ Name = "ScorpTagManagerPanel", Title = "Scorp Tag Studio · Staff", Size = UDim2.fromOffset(540, 660) })
    local status, usersLabel
    local usernameBox, targetBox, titleBox, reasonBox
    local activeUsers, rolePicker, tierPicker, effectPicker, colorPicker, freeColorPicker
    local userChoices = {}

    local function notify(message, isError)
        Window:Notify(isError and "Tag Studio" or "Tag Studio", message, 4, isError and Window.Theme.Danger or Window.Theme.Success)
    end

    local function call(path, body)
        local options = {
            Url = ctx.server .. path,
            Method = body and "POST" or "GET",
            Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. tostring(ctx.token) },
        }
        if body then options.Body = HttpService:JSONEncode(body) end
        local ok, response = pcall(ctx.request, options)
        if not ok or type(response) ~= "table" then return nil, "Request failed." end
        local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
        if not decoded or type(data) ~= "table" then return nil, "Server response could not be read." end
        if response.StatusCode ~= 200 or data.ok == false then return nil, data.error or ("Request refused (" .. tostring(response.StatusCode) .. ").") end
        return data
    end

    local function setTarget(userId, username)
        targetBox:Set(tostring(userId or ""))
        if username and username ~= "" then usernameBox:Set(username) end
        notify("Selected @" .. tostring(username or userId) .. " · ID " .. tostring(userId))
    end

    local function getTarget()
        local id = targetBox:Get():gsub("%s", "")
        if not id:match("^%d+$") then notify("Choose an active Scorp user or resolve a Roblox username first.", true); return nil end
        return id
    end

    local function refreshUsers()
        local jobId = HttpService:UrlEncode(tostring(game.JobId or ""))
        local data, err = call("/api/panel/active-users?jobId=" .. jobId)
        if not data then usersLabel:Set("Could not load users · " .. tostring(err)); return notify(tostring(err), true) end
        local choices = {}
        userChoices = {}
        for _, user in ipairs(data.users or {}) do
            local name = tostring(user.username or "Unknown")
            local choice = "@" .. name .. " · " .. tostring(user.displayName or name) .. " · " .. tostring(user.userId)
            choices[#choices + 1] = choice
            userChoices[choice] = { userId = user.userId, username = name }
        end
        table.sort(choices)
        activeUsers:Refresh(choices, false)
        usersLabel:Set(#choices == 0 and "No Scorp users are active in this game server." or (tostring(#choices) .. " active Scorp user(s) · select one to fill the target."))
    end

    local function lookupUsername()
        local username = usernameBox:Get():gsub("^@", "")
        if username == "" then return notify("Enter the exact Roblox username.", true) end
        local data, err = call("/api/panel/resolve-user", { username = username })
        if not data then return notify(tostring(err), true) end
        setTarget(data.user.userId, data.user.username)
    end

    local function colorHex(color)
        return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
    end

    local EFFECTS = {
        ["Classic Glow"] = { textAnimation = "default", effects = true, glow = true, pulse = false, spin = true, particles = false, underlineSweep = false, glitch = false, grid = false, logoMotion = false },
        ["Soft Aurora"] = { textAnimation = "shimmer", effects = true, glow = true, pulse = true, spin = false, particles = true, underlineSweep = true, glitch = false, grid = false, logoMotion = true },
        ["Solar Pulse"] = { textAnimation = "wave", effects = true, glow = true, pulse = true, spin = true, particles = false, underlineSweep = true, glitch = false, grid = true, logoMotion = false },
        ["Pixel Trail"] = { textAnimation = "shimmer", effects = true, glow = false, pulse = false, spin = true, particles = true, underlineSweep = false, glitch = true, grid = true, logoMotion = false },
        ["Low-Key"] = { textAnimation = "default", effects = false, glow = false, pulse = false, spin = false, particles = false, underlineSweep = false, glitch = false, grid = false, logoMotion = false },
    }

    local function applyTag()
        local userId = getTarget()
        if not userId then return end
        local title = titleBox:Get():sub(1, 24)
        if title == "" then return notify("Enter the displayed title (up to 24 characters).", true) end
        local effect = EFFECTS[effectPicker:Get()] or EFFECTS["Classic Glow"]
        local body = {
            userId = userId,
            username = usernameBox:Get(),
            role = rolePicker:Get(),
            label = title,
            tier = tierPicker:Get(),
            reason = reasonBox:Get() ~= "" and reasonBox:Get() or "Tag assigned by Scorp tag staff",
        }
        if tierPicker:Get() == "free" then
            body.freePresets = {
                colorPreset = freeColorPicker:Get(),
                fontPreset = "Classic",
                effectPreset = effectPicker:Get(),
            }
        else
            body.options = {
                label = title,
                theme = colorHex(colorPicker:Get()),
                rankFont = "GothamBold",
                userFont = "GothamMedium",
                nameTextSize = 13,
            }
            for key, value in pairs(effect) do body.options[key] = value end
        end
        status:Set("Saving tag…")
        local data, err = call("/api/tag-panel/tag", body)
        if not data then status:Set("Save failed · " .. tostring(err)); return notify(tostring(err), true) end
        status:Set("Saved · @" .. tostring(usernameBox:Get()) .. " · " .. title .. " · " .. tierPicker:Get())
        notify("Tag saved for @" .. tostring(usernameBox:Get()) .. ".")
    end

    do
        local sec = panel:CreateSection("Tag staff workspace", true)
        sec:AddLabel("Tag assignment only · this panel cannot access moderation or account enforcement.", { Wrap = true, Color = Window.Theme.TextDim })
        status = sec:AddLabel("Select a user to begin.", { Wrap = true })
    end

    do
        local sec = panel:CreateSection("Find a player", true)
        usersLabel = sec:AddLabel("Refresh the list to find Scorp users in this game server.", { Wrap = true, Color = Window.Theme.TextDim })
        activeUsers = sec:AddDropdown("Active Scorp users", { Options = {}, Callback = function(choice)
            local user = userChoices[choice]
            if user then setTarget(user.userId, user.username) end
        end })
        sec:AddButton("Refresh active users", refreshUsers)
        usernameBox = sec:AddTextbox("Roblox username", { Default = "", Placeholder = "exact username, not display name" })
        sec:AddButton("Resolve username", lookupUsername)
        targetBox = sec:AddTextbox("Roblox user ID", { Default = "", Placeholder = "filled by player selection or lookup" })
        reasonBox = sec:AddTextbox("Staff note (optional)", { Default = "", Placeholder = "short assignment note" })
    end

    do
        local sec = panel:CreateSection("Assign nametag", true)
        rolePicker = sec:AddDropdown("Public role", { Options = { "member", "vip" }, Default = "member" })
        titleBox = sec:AddTextbox("Displayed title", { Default = "Member", Placeholder = "e.g. Community Support" })
        tierPicker = sec:AddDropdown("Tag tier", { Options = { "premium", "free" }, Default = "premium", Callback = function(tier)
            colorPicker.Frame.Visible = tier == "premium"
            freeColorPicker.Frame.Visible = tier == "free"
        end })
        freeColorPicker = sec:AddDropdown("Free color preset", { Options = { "Silver Surfer", "Power Cosmic", "Lime Noir", "Cyber Blue", "Gold Royal", "Toxic", "Candy", "Aurora", "Rose Gold", "Arctic", "Violet Dream", "Inferno", "Ocean", "Clean Light" }, Default = "Cyber Blue" })
        effectPicker = sec:AddDropdown("Effect style", { Options = { "Classic Glow", "Soft Aurora", "Solar Pulse", "Pixel Trail", "Low-Key" }, Default = "Soft Aurora" })
        colorPicker = sec:AddColorPicker("Tag accent", { Default = Color3.fromRGB(85, 191, 255) })
        freeColorPicker.Frame.Visible = false
        sec:AddLabel("Premium applies individual styling options. Free still gets its assigned role/title and a curated effect style.", { Wrap = true, Color = Window.Theme.TextDim })
        sec:AddButton("Save Tag Assignment", applyTag)
    end

    local api = {}
    function api.Open()
        panel:Show()
        task.defer(refreshUsers)
    end
    function api.Destroy() pcall(function() panel:Hide() end) end
    return api
end

return TagPanel
