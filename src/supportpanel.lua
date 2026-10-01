-- ───────────────────────────────────────────────────────────────────────────
-- Scorp support panel. Support can submit reports and pause Scorp access only.
-- Moderation and role changes remain in the full admin panel.
-- Lua 5.1 syntax only (the obfuscator parses 5.1).
-- ───────────────────────────────────────────────────────────────────────────
local SupportPanel = {}

function SupportPanel.Build(Window, ctx)
    local HttpService = game:GetService("HttpService")
    local panel = Window:CreatePopout({ Name = "ScorpSupportPanel", Title = "Scorp Support Desk", Size = UDim2.fromOffset(540, 640) })
    local status
    local categoryPicker, reportSubject, reportDetails, reportTarget
    local actionTarget, actionReason, pausePicker

    local function notify(message, isError)
        Window:Notify(isError and "Support Desk" or "Scorp Support", message, 5, isError and Window.Theme.Danger or Window.Theme.Success)
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
        if response.StatusCode ~= 200 or data.ok == false then
            return nil, data.error or data.message or ("Request refused (" .. tostring(response.StatusCode) .. ").")
        end
        return data
    end

    local function submitReport()
        local subject = reportSubject:Get():sub(1, 100)
        local details = reportDetails:Get():sub(1, 1800)
        if subject == "" or #details < 20 then return notify("Add a subject and at least 20 characters of detail.", true) end
        local target = reportTarget:Get():gsub("%s", "")
        if target ~= "" and not target:match("^%d+$") then return notify("Target ID must be numeric, or leave it blank.", true) end
        status:Set("Sending report to Scorp staff…")
        local data, err = call("/api/support-panel/report", {
            category = categoryPicker:Get(),
            subject = subject,
            details = details,
            targetUserId = target ~= "" and target or nil,
        })
        if not data then status:Set("Report was not sent."); return notify(tostring(err), true) end
        status:Set("Report filed · " .. tostring(data.report.id) .. " · staff have been notified.")
        notify("Report sent to Scorp staff · " .. tostring(data.report.id))
    end

    local function endSession()
        local userId = actionTarget:Get():gsub("%s", "")
        local reason = actionReason:Get():sub(1, 300)
        if not userId:match("^%d+$") then return notify("Enter a numeric Roblox user ID.", true) end
        if #reason < 8 then return notify("Enter a reason of at least 8 characters.", true) end
        local durationByLabel = { ["5 minutes"] = 5, ["15 minutes"] = 15, ["1 hour"] = 60, ["24 hours"] = 1440 }
        local durationMinutes = durationByLabel[pausePicker:Get()]
        if not durationMinutes then return notify("Choose a valid session pause duration.", true) end
        local data, err = call("/api/support-panel/end-session", {
            userId = userId,
            reason = reason,
            durationMinutes = durationMinutes,
        })
        if not data then return notify(tostring(err), true) end
        notify("Scorp session stopped; access paused until " .. tostring(data["until"]))
    end

    do
        local section = panel:CreateSection("Support desk", true)
        section:AddLabel("Reports notify the configured Scorp owner/admins in Discord. Support can pause Scorp access, but cannot issue blacklists or kick someone from the Roblox game server.", { Wrap = true, Color = Window.Theme.TextDim })
        status = section:AddLabel("Ready to help.", { Wrap = true })
    end

    do
        local section = panel:CreateSection("File a report", true)
        categoryPicker = section:AddDropdown("Report category", { Options = { "behavior", "harassment", "cheating", "exploiting", "other" }, Default = "behavior" })
        reportTarget = section:AddTextbox("Target Roblox ID (optional)", { Default = "", Placeholder = "numeric ID, if known" })
        reportSubject = section:AddTextbox("Short subject", { Default = "", Placeholder = "What happened?" })
        reportDetails = section:AddTextbox("Report details", { Default = "", Placeholder = "Include context and when it happened" })
        section:AddButton("Submit Report", submitReport)
    end

    do
        local section = panel:CreateSection("End a Scorp session", false)
        section:AddLabel("Stops Scorp on the target's current client and blocks relaunch until the pause expires. This does not remove them from the Roblox game.", { Wrap = true, Color = Window.Theme.TextDim })
        actionTarget = section:AddTextbox("Target Roblox ID", { Default = "", Placeholder = "numeric ID" })
        actionReason = section:AddTextbox("Reason", { Default = "", Placeholder = "brief support note" })
        pausePicker = section:AddDropdown("Pause duration", { Options = { "5 minutes", "15 minutes", "1 hour", "24 hours" }, Default = "15 minutes" })
        section:AddButton("End Scorp Session", endSession)
    end

    local api = {}
    function api.Open() panel:Show() end
    function api.Destroy() pcall(function() panel:Hide() end) end
    return api
end

return SupportPanel
