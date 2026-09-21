-- A player respawns (new Head instance): the tag must move to the new head.
return function(H)
    H.runLoader()
    H.advance(12)
    local before = H.tags()
    local players = game:GetService("Players"):GetPlayers()
    for _, p in ipairs(players) do
        if p.Name == "Drew" then
            local newHead = Instance.new("Part") newHead.Name = "Head"
            p.Character:FindFirstChild("Head"):Destroy()
            newHead.Parent = p.Character
        end
    end
    H.advance(3)
    H.result({ before = before, after = H.tags() })
end
