-- ───────────────────────────────────────────────────────────────────────────
-- Scorp in-game staff panel. Server access is still enforced by /api/panel/*.
-- Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────
local AdminPanel = {}

function AdminPanel.Build(Window, ctx)
    local request = ctx.request
    local HttpService = game:GetService("HttpService")
    local panel = Window:CreatePopout({ Name = "ScorpAdminPanel", Title = "Scorp Admin Panel", Size = UDim2.fromOffset(560, 700) })
    local statusLabel
    local targetBox, reasonBox, titleBox

    local function notify(message, isError)
        Window:Notify(isError and "Admin Panel" or "Scorp Admin", message, 4, isError and Window.Theme.Danger or Window.Theme.Success)
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

    local function refresh()
        statusLabel:Set("Loading staff overview…")
        local data, err = call("/api/panel/overview")
        if not data then
            statusLabel:Set("Not authorized or unavailable: " .. tostring(err))
            notify(tostring(err), true)
            return false
        end
        local lines = {
            "BUILD  " .. tostring(data.build and data.build.id or "unavailable"),
            "ONLINE  " .. tostring(data.usersOnline or 0) .. "  ·  SESSIONS  " .. tostring(data.sessions and data.sessions.tracked or 0),
            "WEBHOOK  " .. ((data.webhook and data.webhook.configured) and "configured" or "not configured"),
            "PREMIUM TAGS  " .. tostring(#(data.paidTags or {})),
            "",
            "BLACKLISTED",
        }
        local active = 0
        for _, item in ipairs((data.access and data.access.blacklisted) or {}) do
            if item.active then
                active = active + 1
                local latest = item.latestReason or {}
                lines[#lines + 1] = "• " .. tostring(latest.userId or (item.identities and item.identities[1]) or "unknown") .. " — " .. tostring(latest.reason or "No reason")
            end
        end
        if active == 0 then lines[#lines + 1] = "• none" end
        lines[#lines + 1] = "ALLOWLISTED"
        local allowed = (data.access and data.access.allowlisted) or {}
        if #allowed == 0 then lines[#lines + 1] = "• none" end
        for _, item in ipairs(allowed) do lines[#lines + 1] = "• " .. tostring(item.userId) .. " — " .. tostring(item.reason or "approved") end
        lines[#lines + 1] = "RECENT STAFF HISTORY"
        local history = data.history or {}
        if #history == 0 then lines[#lines + 1] = "• none" end
        for i = 1, math.min(#history, 8) do
            local event = history[i]
            lines[#lines + 1] = "• " .. tostring(event.action) .. " · " .. tostring(event.userId or event.target or "—") .. (event.reason and (" · " .. tostring(event.reason)) or "")
        end
        statusLabel:Set(table.concat(lines, "\n"):sub(1, 6000))
        return true
    end

    do
        local sec = panel:CreateSection("Staff Overview", true)
        sec:AddLabel("Server-authorized controls for configured Roblox staff accounts. Every action is checked and recorded by the backend.", { Wrap = true })
        statusLabel = sec:AddLabel("Open the panel or press Refresh to load server data.", { Wrap = true, Color = Window.Theme.TextDim })
        sec:AddButton("Refresh Overview", refresh)
    end

    do
        local sec = panel:CreateSection("Account Access", true)
        targetBox = sec:AddTextbox("Roblox User ID", { Default = "", Placeholder = "numeric user id" })
        reasonBox = sec:AddTextbox("Reason / Note", { Default = "", Placeholder = "brief staff note" })
        sec:AddButton("Blacklist Permanently", function()
            local id, reason = targetBox:Get(), reasonBox:Get()
            if id == "" or reason == "" then return notify("Enter a Roblox ID and reason.", true) end
            local data, err = call("/api/panel/blacklist", { userId = id, reason = reason, permanent = true })
            if not data then return notify(tostring(err), true) end
            notify("Blacklist recorded with reason.")
            refresh()
        end)
        sec:AddButton("Allowlist for Auto-Detection", function()
            local id, reason = targetBox:Get(), reasonBox:Get()
            if id == "" then return notify("Enter a Roblox ID.", true) end
            local data, err = call("/api/panel/allowlist", { userId = id, reason = reason, allowed = true })
            if not data then return notify(tostring(err), true) end
            notify("Allowlist updated; manual blacklists still apply.")
            refresh()
        end)
        sec:AddButton("Remove from Allowlist", function()
            local id = targetBox:Get()
            if id == "" then return notify("Enter a Roblox ID.", true) end
            local data, err = call("/api/panel/allowlist", { userId = id, allowed = false })
            if not data then return notify(tostring(err), true) end
            notify("Allowlist entry removed.")
            refresh()
        end)
        sec:AddButton("Lift Blacklist", function()
            local id = targetBox:Get()
            if id == "" then return notify("Enter a Roblox ID.", true) end
            local data, err = call("/api/panel/unblacklist", { target = id })
            if not data then return notify(tostring(err), true) end
            notify("Blacklist lifted.")
            refresh()
        end)
        sec:AddButton("Edit Latest Blacklist Reason", function()
            local id, reason = targetBox:Get(), reasonBox:Get()
            if id == "" or reason == "" then return notify("Enter a Roblox ID and updated reason.", true) end
            local data, err = call("/api/panel/blacklist/reason", { target = id, reason = reason })
            if not data then return notify(tostring(err), true) end
            notify("Blacklist reason updated.")
            refresh()
        end)
    end

    do
        local sec = panel:CreateSection("Paid Name Tags", true)
        sec:AddLabel("Premium title/prefix text is staff-assigned. The Roblox display name and discord.gg/scorp remain visible; custom text cannot replace or impersonate the account.", { Wrap = true })
        titleBox = sec:AddTextbox("Approved Tag Title", { Default = "", Placeholder = "role/title text, max 24 characters" })
        sec:AddButton("Grant Premium + Set Title", function()
            local id, title, reason = targetBox:Get(), titleBox:Get(), reasonBox:Get()
            if id == "" or title == "" then return notify("Enter a Roblox ID and approved title.", true) end
            local data, err = call("/api/panel/tag", { userId = id, tier = "premium", reason = reason, options = { label = title } })
            if not data then return notify(tostring(err), true) end
            notify("Premium tag entitlement and approved title saved.")
            refresh()
        end)
        sec:AddButton("Revoke Premium Entitlement", function()
            local id = targetBox:Get()
            if id == "" then return notify("Enter a Roblox ID.", true) end
            local data, err = call("/api/panel/tag", { userId = id, tier = "free", reason = reasonBox:Get() })
            if not data then return notify(tostring(err), true) end
            notify("Premium entitlement revoked.")
            refresh()
        end)
    end

    local api = {}
    function api.Open()
        panel:Show()
        task.defer(refresh)
    end
    function api.Destroy() pcall(function() panel:Hide() end) end
    return api
end

return AdminPanel
