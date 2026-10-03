-- Informational roster for players already in the current Roblox server.
-- No follow, teleport, surveillance, or target actions are exposed here.
local PlayerRoster = {}

function PlayerRoster.Build(Window, Players, LocalPlayer)
    local tab = Window:CreateTab("Players", { Icon = "♙", Group = "Workspace" })
    local rosterDropdown
    local detail
    local choicesByLabel = {}
    local connections = {}

    local function refresh()
        local choices = {}
        choicesByLabel = {}
        local current = Players:GetPlayers()
        table.sort(current, function(a, b)
            return tostring(a.DisplayName or a.Name):lower() < tostring(b.DisplayName or b.Name):lower()
        end)
        for _, player in ipairs(current) do
            local display = tostring(player.DisplayName or player.Name)
            local choice = display .. "  ·  @" .. tostring(player.Name)
            choices[#choices + 1] = choice
            choicesByLabel[choice] = player
        end
        rosterDropdown:Refresh(choices, false)
        detail:Set(tostring(#current) .. " player(s) currently in this game server. This list is informational only.")
    end

    do
        local section = tab:CreateSection("CURRENT SERVER", true)
        section:AddLabel("A read-only view of players in this Roblox server. It does not track players outside this server.", {
            Wrap = true, Color = Window.Theme.TextDim,
        })
        rosterDropdown = section:AddDropdown("Players here", { Options = {}, Callback = function(choice)
            local player = choicesByLabel[choice]
            if not player then return end
            local relationship = player == LocalPlayer and "You" or "In this server"
            detail:Set(relationship .. "  ·  " .. tostring(player.DisplayName or player.Name) .. "  ·  @" .. player.Name)
        end })
        detail = section:AddLabel("Refresh to load the current server roster.", { Wrap = true })
        section:AddButton("Refresh Player List", refresh)
    end

    connections[#connections + 1] = Players.PlayerAdded:Connect(function() task.defer(refresh) end)
    connections[#connections + 1] = Players.PlayerRemoving:Connect(function() task.defer(refresh) end)

    local api = {}
    function api.Open()
        Window:Toggle(true)
        Window:SelectTab(tab)
    end
    function api.Refresh() refresh() end
    function api.Destroy()
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        connections = {}
    end
    task.defer(refresh)
    return api
end

return PlayerRoster
