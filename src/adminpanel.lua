-- ───────────────────────────────────────────────────────────────────────────
-- Scorp in-game staff panel. Every write is authorized and validated server-side.
-- Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────
local AdminPanel = {}

function AdminPanel.Build(Window, ctx)
    local request = ctx.request
    local HttpService = game:GetService("HttpService")
    local panel = Window:CreatePopout({ Name = "ScorpAdminPanel", Title = "Scorp Staff Console", Size = UDim2.fromOffset(560, 700) })
    local statusLabel, detailsLabel, playersLabel, accessListsLabel, supportReportsLabel
    local targetBox, usernameBox, reasonBox, roleTextBox, colorTextBox
    local activePlayers, rolePicker, colorPicker, redSlider, greenSlider, blueSlider, banDurationPicker
    local activeByChoice = {}

    local function notify(message, isError)
        Window:Notify(isError and "Staff Console" or "Scorp Staff", message, 4, isError and Window.Theme.Danger or Window.Theme.Success)
    end

    local function call(path, body)
        local options = {
            Url = ctx.server .. path,
            Method = body and "POST" or "GET",
            Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. tostring(ctx.token) },
        }
        if body then options.Body = HttpService:JSONEncode(body) end
        local ok, response = pcall(request, options)
        if not ok or type(response) ~= "table" then return nil, "Request failed." end
        local decodedOk, data = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
        if not decodedOk or type(data) ~= "table" then return nil, "Server returned an unreadable response." end
        if response.StatusCode ~= 200 or data.ok == false then
            return nil, data.error or ("Request refused (" .. tostring(response.StatusCode) .. ").")
        end
        return data
    end

    local function refreshOverview()
        local data, err = call("/api/panel/overview")
        if not data then
            statusLabel:Set("Overview unavailable · " .. tostring(err))
            notify(tostring(err), true)
            return false
        end
        local activeBans, allowlisted = 0, 0
        for _, item in ipairs((data.access and data.access.blacklisted) or {}) do
            if item.active then activeBans = activeBans + 1 end
        end
        allowlisted = #((data.access and data.access.allowlisted) or {})
        statusLabel:Set(table.concat({
            "●  SERVER STATUS",
            "Online  " .. tostring(data.usersOnline or 0) .. "     Sessions  " .. tostring(data.sessions and data.sessions.tracked or 0),
            "Active blacklists  " .. tostring(activeBans) .. "     Allowlisted  " .. tostring(allowlisted),
            "Premium tags  " .. tostring(#(data.paidTags or {})) .. "     Webhook  " .. ((data.webhook and data.webhook.configured) and "Connected" or "Not configured"),
            "Build  " .. tostring(data.build and data.build.id or "unavailable"),
        }, "\n"))

        local rows = { "RECENT STAFF ACTIVITY" }
        local history = data.history or {}
        for i = 1, math.min(#history, 4) do
            local event = history[i]
            rows[#rows + 1] = "• " .. tostring(event.action or "action") .. " · " .. tostring(event.userId or event.target or "—")
        end
        if #history == 0 then rows[#rows + 1] = "• No recent actions" end
        detailsLabel:Set(table.concat(rows, "\n"))

        local accessRows = { "ACTIVE BLACKLISTS" }
        local blacklists = data.access and data.access.blacklisted or {}
        local shown = 0
        for _, item in ipairs(blacklists) do
            if item.active and shown < 6 then
                shown = shown + 1
                local latest = item.latestReason or {}
                local identity = tostring(latest.username or "Account") .. " · " .. tostring(latest.userId or "unknown")
                local duration = item.permanent and "permanent" or "temporary"
                accessRows[#accessRows + 1] = "• " .. identity .. " · " .. duration .. " · " .. tostring(latest.reason or "No reason"):sub(1, 70)
            end
        end
        if shown == 0 then accessRows[#accessRows + 1] = "• None" end
        accessRows[#accessRows + 1] = "ALLOWLISTED"
        local allowlist = data.access and data.access.allowlisted or {}
        for i = 1, math.min(#allowlist, 6) do
            local item = allowlist[i]
            accessRows[#accessRows + 1] = "• " .. tostring(item.username or item.userId or "Unknown") .. " · " .. tostring(item.userId or "—")
        end
        if #allowlist == 0 then accessRows[#accessRows + 1] = "• None" end
        if accessListsLabel then accessListsLabel:Set(table.concat(accessRows, "\n")) end
        return true
    end

    local function setTarget(id, username)
        id = tostring(id or "")
        targetBox:Set(id)
        if username and username ~= "" then usernameBox:Set(username) end
        notify("Selected @" .. tostring(username or id) .. " · ID " .. id)
    end

    local function refreshPlayers()
        local jobId = HttpService:UrlEncode(tostring(game.JobId or ""))
        local data, err = call("/api/panel/active-users?jobId=" .. jobId)
        if not data then
            playersLabel:Set("Could not load active users · " .. tostring(err))
            return notify(tostring(err), true)
        end
        activeByChoice = {}
        local choices = {}
        for _, user in ipairs(data.users or {}) do
            local username = tostring(user.username or "Unknown")
            local displayName = tostring(user.displayName or username)
            local id = tostring(user.userId or "")
            local choice = "@" .. username .. " · " .. displayName .. " · " .. id
            activeByChoice[choice] = { userId = id, username = username }
            choices[#choices + 1] = choice
        end
        table.sort(choices)
        activePlayers:Refresh(choices, false)
        playersLabel:Set(#choices == 0 and "No active Scorp users in this server right now." or ("" .. #choices .. " active account(s) · choose a player to load their ID below."))
    end

    local function refreshSupportReports()
        local data, err = call("/api/panel/support/reports")
        if not data then
            supportReportsLabel:Set("Support queue unavailable · " .. tostring(err))
            return notify(tostring(err), true)
        end
        local rows = { "RECENT SUPPORT REPORTS" }
        local reports = data.reports or {}
        for i = 1, math.min(#reports, 8) do
            local report = reports[i]
            rows[#rows + 1] = "• " .. tostring(report.id) .. " · " .. tostring(report.category) .. " · target " .. tostring(report.targetUserId or "—")
            rows[#rows + 1] = "  " .. tostring(report.subject):sub(1, 100)
            rows[#rows + 1] = "  " .. tostring(report.details):sub(1, 220)
        end
        if #reports == 0 then rows[#rows + 1] = "• No reports filed" end
        supportReportsLabel:Set(table.concat(rows, "\n"))
    end

    local function lookupUsername()
        local username = usernameBox:Get():gsub("^@", "")
        if username == "" then return notify("Enter a Roblox username first.", true) end
        local data, err = call("/api/panel/resolve-user", { username = username })
        if not data then return notify(tostring(err), true) end
        setTarget(data.user.userId, data.user.username)
    end

    local function targetId()
        local id = targetBox:Get():gsub("%s", "")
        if not id:match("^%d+$") then notify("Select a player or enter a numeric Roblox ID.", true); return nil end
        return id
    end

    local function colorHex(color)
        return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
    end

    local function setRgbColor(red, green, blue)
        local color = Color3.fromRGB(red, green, blue)
        colorTextBox:Set(colorHex(color), true)
        if colorPicker then colorPicker:Set(color, true) end
        if redSlider then redSlider:Set(red, true); greenSlider:Set(green, true); blueSlider:Set(blue, true) end
    end

    local function syncRgbSliders()
        if not (redSlider and greenSlider and blueSlider) then return end
        setRgbColor(redSlider:Get(), greenSlider:Get(), blueSlider:Get())
    end

    local function copyId()
        local id = targetId()
        if not id then return end
        local copy = setclipboard or toclipboard
        if type(copy) == "function" then
            local ok = pcall(copy, id)
            if ok then return notify("Copied Roblox ID " .. id) end
        end
        notify("Roblox ID: " .. id)
    end

    do
        local sec = panel:CreateSection("01 · Overview", true)
        sec:AddLabel("Server-authorized controls · every action is checked and audited.", { Wrap = true, Color = Window.Theme.TextDim })
        statusLabel = sec:AddLabel("Loading staff overview…", { Wrap = true, TextSize = 12 })
        sec:AddButton("Refresh Overview", refreshOverview)
        detailsLabel = sec:AddLabel("RECENT STAFF ACTIVITY\nLoading…", { Wrap = true, Color = Window.Theme.TextDim, TextSize = 11 })
    end

    do
        local sec = panel:CreateSection("02 · Access Review", false)
        sec:AddButton("Refresh Access Lists", refreshOverview)
        accessListsLabel = sec:AddLabel("Refresh to review active blacklists and allowlisted accounts.", { Wrap = true, Color = Window.Theme.TextDim, TextSize = 11 })
    end

    do
        local sec = panel:CreateSection("03 · Find a Player", true)
        playersLabel = sec:AddLabel("Refresh to find script users in the current server.", { Wrap = true, Color = Window.Theme.TextDim })
        activePlayers = sec:AddDropdown("Active Script Users", { Options = {}, Callback = function(choice)
            local user = activeByChoice[choice]
            if user then setTarget(user.userId, user.username) end
        end })
        sec:AddButton("Refresh Active Players", refreshPlayers)
        sec:AddButton("Copy Selected ID", copyId)
        usernameBox = sec:AddTextbox("Roblox Username", { Default = "", Placeholder = "username (not display name)" })
        sec:AddButton("Find Username → Fill ID", lookupUsername)
        targetBox = sec:AddTextbox("Selected Roblox ID", { Default = "", Placeholder = "choose a player or look one up" })
        reasonBox = sec:AddTextbox("Reason / Note", { Default = "", Placeholder = "brief staff note" })
    end

    do
        local sec = panel:CreateSection("04 · Account Actions", false)
        sec:AddLabel("Choose an active user above or resolve a Roblox username, then select an action.", { Wrap = true, Color = Window.Theme.TextDim })
        banDurationPicker = sec:AddDropdown("Ban duration", { Options = { "Tiered by offense", "1 hour", "6 hours", "1 day", "1 week", "1 month", "Permanent" }, Default = "Tiered by offense" })
        sec:AddButton("Apply Selected Ban Duration", function()
            local id, reason = targetId(), reasonBox:Get()
            if not id then return end
            if reason == "" then return notify("Add a brief reason for the ban.", true) end
            local duration = banDurationPicker:Get()
            local seconds = { ["1 hour"] = 3600, ["6 hours"] = 21600, ["1 day"] = 86400, ["1 week"] = 604800, ["1 month"] = 2592000 }
            local body = { userId = id, username = usernameBox:Get(), reason = reason, permanent = duration == "Permanent" }
            if seconds[duration] then body.durationSeconds = seconds[duration] end
            local data, err = call("/api/panel/blacklist", body)
            if not data then return notify(tostring(err), true) end
            notify("Blacklist recorded · " .. (duration == "Tiered by offense" and "offense tier" or duration))
            refreshOverview()
        end)
        sec:AddButton("Blacklist Permanently", function()
            local id, reason = targetId(), reasonBox:Get()
            if not id then return end
            if reason == "" then return notify("Add a brief reason for the blacklist.", true) end
            local data, err = call("/api/panel/blacklist", { userId = id, username = usernameBox:Get(), reason = reason, permanent = true })
            if not data then return notify(tostring(err), true) end
            notify("Permanent blacklist recorded.")
            refreshOverview()
        end)
        sec:AddButton("Allowlist for Auto-Detection", function()
            local id = targetId()
            if not id then return end
            local data, err = call("/api/panel/allowlist", { userId = id, reason = reasonBox:Get(), allowed = true })
            if not data then return notify(tostring(err), true) end
            notify("Allowlist updated; manual blacklists still apply.")
            refreshOverview()
        end)
        sec:AddButton("Remove from Allowlist", function()
            local id = targetId()
            if not id then return end
            local data, err = call("/api/panel/allowlist", { userId = id, allowed = false })
            if not data then return notify(tostring(err), true) end
            notify("Allowlist entry removed.")
            refreshOverview()
        end)
        sec:AddButton("Lift Blacklist", function()
            local id = targetId()
            if not id then return end
            local data, err = call("/api/panel/unblacklist", { target = id })
            if not data then return notify(tostring(err), true) end
            notify("Blacklist lifted.")
            refreshOverview()
        end)
        sec:AddButton("Edit Latest Blacklist Reason", function()
            local id, reason = targetId(), reasonBox:Get()
            if not id then return end
            if reason == "" then return notify("Enter the updated reason.", true) end
            local data, err = call("/api/panel/blacklist/reason", { target = id, reason = reason })
            if not data then return notify(tostring(err), true) end
            notify("Blacklist reason updated.")
            refreshOverview()
        end)
    end

    do
        local sec = panel:CreateSection("05 · Support Review", false)
        sec:AddLabel("Review submitted reports here. Verify details before applying a blacklist or temporary ban.", { Wrap = true, Color = Window.Theme.TextDim })
        supportReportsLabel = sec:AddLabel("Refresh to load recent support reports.", { Wrap = true, Color = Window.Theme.TextDim, TextSize = 11 })
        sec:AddButton("Refresh Support Reports", refreshSupportReports)
    end

    do
        local sec = panel:CreateSection("06 · Nametag Design", false)
        sec:AddLabel("Set the account role, displayed role text, and a custom accent color. The Roblox username remains visible.", { Wrap = true, Color = Window.Theme.TextDim })
        rolePicker = sec:AddDropdown("Role", { Options = { "owner", "developer", "admin", "moderator", "support", "vip", "member" }, Default = "member" })
        roleTextBox = sec:AddTextbox("Role Text", { Default = "", Placeholder = "text shown on the tag (max 24)" })
        colorTextBox = sec:AddTextbox("Color (HEX / RGB)", { Default = "#3CC8FF", Placeholder = "#3CC8FF or 60,200,255" })
        colorPicker = sec:AddColorPicker("Pick Accent Color", {
            Default = Color3.fromRGB(60, 200, 255),
            Callback = function(color)
                setRgbColor(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
            end,
        })
        redSlider = sec:AddSlider("Red", { Min = 0, Max = 255, Default = 60, Callback = syncRgbSliders })
        greenSlider = sec:AddSlider("Green", { Min = 0, Max = 255, Default = 200, Callback = syncRgbSliders })
        blueSlider = sec:AddSlider("Blue", { Min = 0, Max = 255, Default = 255, Callback = syncRgbSliders })
        sec:AddButton("Apply Role + Text + Color", function()
            local id = targetId()
            if not id then return end
            local label = roleTextBox:Get():sub(1, 24)
            local color = colorTextBox:Get():gsub("%s", "")
            if color:match("^%d+,%d+,%d+$") then
                local r, g, b = color:match("^(%d+),(%d+),(%d+)$")
                r, g, b = tonumber(r), tonumber(g), tonumber(b)
                if r > 255 or g > 255 or b > 255 then return notify("RGB channels must be between 0 and 255.", true) end
                color = string.format("#%02X%02X%02X", r, g, b)
            end
            if not color:match("^#?%x%x%x%x%x%x$") then return notify("Use a six-digit hex color or RGB values such as 60,200,255.", true) end
            if color:sub(1, 1) ~= "#" then color = "#" .. color end
            local red = tonumber(color:sub(2, 3), 16)
            local green = tonumber(color:sub(4, 5), 16)
            local blue = tonumber(color:sub(6, 7), 16)
            setRgbColor(red, green, blue)
            if label == "" then return notify("Enter the displayed role text.", true) end
            local body = {
                userId = id,
                role = rolePicker:Get(),
                label = label,
                tier = "premium",
                reason = reasonBox:Get() ~= "" and reasonBox:Get() or "In-game staff nametag design",
                options = { label = label, primary = color },
            }
            local data, err = call("/api/panel/tag", body)
            if not data then return notify(tostring(err), true) end
            notify("Role, title text, and custom accent saved.")
            refreshOverview()
        end)
        sec:AddButton("Revoke Premium Tag Access", function()
            local id = targetId()
            if not id then return end
            local data, err = call("/api/panel/tag", { userId = id, tier = "free", reason = reasonBox:Get() })
            if not data then return notify(tostring(err), true) end
            notify("Premium tag entitlement revoked.")
            refreshOverview()
        end)
    end

    local api = {}
    function api.Open()
        panel:Show()
        task.defer(refreshOverview)
        task.defer(refreshPlayers)
        task.defer(refreshSupportReports)
    end
    function api.Destroy() pcall(function() panel:Hide() end) end
    return api
end

return AdminPanel