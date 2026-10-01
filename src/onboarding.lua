-- Scorp intro, first-run guide and safe audio helpers. Lua 5.1 compatible.
local Onboarding = {}
local UserInputService = game:GetService("UserInputService")

local AUDIO = {
    intro = { url = "https://files.catbox.moe/9rl7lj.mp3", file = "Scorp/Audio/intro.mp3" },
    click = { url = "https://files.catbox.moe/d3vs2r.mp3", file = "Scorp/Audio/click.mp3" },
    hover = { url = "", file = "Scorp/Audio/hover.mp3" },
}

local function validMp3(data)
    if type(data) ~= "string" or #data < 1000 or #data > 8 * 1024 * 1024 then return false end
    if data:sub(1, 3) == "ID3" then return true end
    local limit = math.min(#data - 1, 4096)
    for i = 1, limit do
        local first, second = data:byte(i, i + 1)
        if first == 255 and second and second >= 224 then return true end
    end
    return false
end

local function assetFunction()
    if type(getcustomasset) == "function" then return getcustomasset end
    if type(getsynasset) == "function" then return getsynasset end
    return nil
end

local function fetchAudio(ctx, item)
    if type(item.url) ~= "string" or item.url == "" then return nil end
    local asset = assetFunction()
    if not asset or type(writefile) ~= "function" or type(isfile) ~= "function" then return nil end
    if type(isfolder) == "function" and type(makefolder) == "function" then
        pcall(function() if not isfolder("Scorp") then makefolder("Scorp") end end)
        pcall(function() if not isfolder("Scorp/Audio") then makefolder("Scorp/Audio") end end)
    end

    if not isfile(item.file) then
        local body
        if ctx and type(ctx.request) == "function" then
            local ok, response = pcall(ctx.request, { Url = item.url, Method = "GET" })
            if ok and type(response) == "table" and (tonumber(response.StatusCode) or 0) >= 200 and (tonumber(response.StatusCode) or 0) < 300 then
                body = response.Body
            end
        end
        if not validMp3(body) then
            local ok, downloaded = pcall(function() return game:HttpGet(item.url) end)
            body = ok and downloaded or nil
        end
        if not validMp3(body) then return nil end
        local saved = pcall(writefile, item.file, body)
        if not saved then return nil end
    end

    local ok, id = pcall(asset, item.file)
    if ok and type(id) == "string" and id ~= "" then return id end
    return nil
end

local function attachGui(gui)
    local parent
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok then parent = result end
    end
    parent = parent or game:GetService("CoreGui")
    local ok = pcall(function() gui.Parent = parent end)
    if not ok or gui.Parent ~= parent then gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end
end

local function inGameConditions()
    local lighting = game:GetService("Lighting")
    local clock = tonumber(lighting.ClockTime) or 12
    local phase = "Day"
    if clock < 5 or clock >= 20 then phase = "Night"
    elseif clock < 7 then phase = "Dawn"
    elseif clock >= 17 then phase = "Dusk" end
    return string.format("IN-GAME SKY  ·  %s  ·  %02d:%02d", phase, math.floor(clock) % 24, math.floor((clock % 1) * 60))
end

local function buildWelcome(Scorp, Window, LocalPlayer, ctx, seen)
    local gui = Instance.new("ScreenGui")
    gui.Name = "ScorpWelcome"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 1300
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    attachGui(gui)

    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
    backdrop.BackgroundTransparency = 0.2
    backdrop.BorderSizePixel = 0
    backdrop.Parent = gui

    local card = Instance.new("Frame")
    card.Name = "WelcomeCard"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.new(0.82, 0, 0.82, 0)
    card.BackgroundColor3 = Window.Theme.MainBg
    card.BorderSizePixel = 0
    card.Parent = backdrop
    local bounds = Instance.new("UISizeConstraint")
    bounds.MinSize = Vector2.new(520, 420)
    bounds.MaxSize = Vector2.new(940, 620)
    bounds.Parent = card
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = card
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Transparency = 0.15
    stroke.Color = Window.Theme.Accent
    stroke.Parent = card
    local cardGradient = Instance.new("UIGradient")
    cardGradient.Rotation = -35
    cardGradient.Color = ColorSequence.new(Window.Theme.MainBg, Window.Theme.ToggleOff)
    cardGradient.Parent = card

    local header = Instance.new("Frame")
    header.BackgroundTransparency = 1
    header.Position = UDim2.fromOffset(28, 24)
    header.Size = UDim2.new(1, -56, 0, 84)
    header.Parent = card
    local brand = Instance.new("TextLabel")
    brand.BackgroundTransparency = 1
    brand.Size = UDim2.new(1, 0, 0, 18)
    brand.Font = Enum.Font.GothamBold
    brand.Text = "✦   SCORP COMMUNITY EXPERIENCE"
    brand.TextColor3 = Window.Theme.AccentLight
    brand.TextSize = 11
    brand.TextXAlignment = Enum.TextXAlignment.Left
    brand.Parent = header
    local greeting = Instance.new("TextLabel")
    greeting.BackgroundTransparency = 1
    greeting.Position = UDim2.fromOffset(0, 23)
    greeting.Size = UDim2.new(1, 0, 0, 34)
    greeting.Font = Enum.Font.GothamBlack
    greeting.Text = seen and "WELCOME BACK, " .. tostring(LocalPlayer.DisplayName or LocalPlayer.Name):upper() or "WELCOME TO SCORP"
    greeting.TextColor3 = Window.Theme.TextWhite
    greeting.TextSize = 23
    greeting.TextXAlignment = Enum.TextXAlignment.Left
    greeting.TextTruncate = Enum.TextTruncate.AtEnd
    greeting.Parent = header
    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.fromOffset(0, 60)
    sub.Size = UDim2.new(1, 0, 0, 20)
    sub.Font = Enum.Font.Montserrat
    sub.Text = "Style your nametag and personalize your Scorp experience."
    sub.TextColor3 = Window.Theme.TextDim
    sub.TextSize = 12
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = header

    local divider = Instance.new("Frame")
    divider.Position = UDim2.new(0, 28, 0, 116)
    divider.Size = UDim2.new(1, -56, 0, 1)
    divider.BackgroundColor3 = Window.Theme.Accent
    divider.BackgroundTransparency = 0.65
    divider.BorderSizePixel = 0
    divider.Parent = card

    local releaseTitle = Instance.new("TextLabel")
    releaseTitle.BackgroundTransparency = 1
    releaseTitle.Position = UDim2.fromOffset(30, 120)
    releaseTitle.Size = UDim2.new(0.53, -34, 0, 24)
    releaseTitle.Font = Enum.Font.GothamBold
    releaseTitle.Text = "WHAT'S NEW"
    releaseTitle.TextColor3 = Window.Theme.TextWhite
    releaseTitle.TextSize = 13
    releaseTitle.TextXAlignment = Enum.TextXAlignment.Left
    releaseTitle.Parent = card

    local releaseCard = Instance.new("Frame")
    releaseCard.Position = UDim2.fromOffset(28, 150)
    releaseCard.Size = UDim2.new(0.53, -32, 0, 168)
    releaseCard.BackgroundColor3 = Window.Theme.ToggleOff
    releaseCard.BackgroundTransparency = 0.18
    releaseCard.BorderSizePixel = 0
    releaseCard.Parent = card
    local releaseCorner = Instance.new("UICorner")
    releaseCorner.CornerRadius = UDim.new(0, 12)
    releaseCorner.Parent = releaseCard
    local releaseStroke = Instance.new("UIStroke")
    releaseStroke.Thickness = 1
    releaseStroke.Transparency = 0.55
    releaseStroke.Color = Window.Theme.AccentLight
    releaseStroke.Parent = releaseCard

    local notes = Instance.new("TextLabel")
    notes.BackgroundTransparency = 1
    notes.Position = UDim2.fromOffset(15, 13)
    notes.Size = UDim2.new(1, -30, 1, -26)
    notes.Font = Enum.Font.Montserrat
    notes.TextColor3 = Window.Theme.TextDim
    notes.TextSize = 12
    notes.TextWrapped = true
    notes.TextXAlignment = Enum.TextXAlignment.Left
    notes.TextYAlignment = Enum.TextYAlignment.Top
    notes.Parent = releaseCard
    local releaseNotes = type(ctx.releaseNotes) == "string" and ctx.releaseNotes ~= "" and ctx.releaseNotes or nil
    if releaseNotes then
        notes.Text = releaseNotes:sub(1, 300)
    else
        notes.Text = "• Red & Black and community-inspired themes\n\n• First-run guide and launch dashboard\n\n• Read-only server roster and local visual presets\n\nRelease " .. tostring(ctx.releaseVersion or "unversioned")
    end

    local guideTitle = Instance.new("TextLabel")
    guideTitle.BackgroundTransparency = 1
    guideTitle.Position = UDim2.new(0.53, 10, 0, 120)
    guideTitle.Size = UDim2.new(0.47, -38, 0, 24)
    guideTitle.Font = Enum.Font.GothamBold
    guideTitle.Text = seen and "QUICK TIPS" or "FIRST STEPS"
    guideTitle.TextColor3 = Window.Theme.TextWhite
    guideTitle.TextSize = 13
    guideTitle.TextXAlignment = Enum.TextXAlignment.Left
    guideTitle.Parent = card

    local guideCard = Instance.new("Frame")
    guideCard.Position = UDim2.new(0.53, 8, 0, 150)
    guideCard.Size = UDim2.new(0.47, -36, 0, 168)
    guideCard.BackgroundColor3 = Window.Theme.ToggleOff
    guideCard.BackgroundTransparency = 0.18
    guideCard.BorderSizePixel = 0
    guideCard.Parent = card
    local guideCorner = Instance.new("UICorner")
    guideCorner.CornerRadius = UDim.new(0, 12)
    guideCorner.Parent = guideCard
    local guideStroke = Instance.new("UIStroke")
    guideStroke.Thickness = 1
    guideStroke.Transparency = 0.55
    guideStroke.Color = Window.Theme.AccentLight
    guideStroke.Parent = guideCard

    local instructions = Instance.new("TextLabel")
    instructions.BackgroundTransparency = 1
    instructions.Position = UDim2.fromOffset(15, 13)
    instructions.Size = UDim2.new(1, -30, 1, -26)
    instructions.Font = Enum.Font.Montserrat
    instructions.Text = seen
        and "01   Open Name Tag Studio to choose your style.\n\n02   Change display options in Settings.\n\n03   RightShift opens or hides the menu.\n\n04   Delete unloads Scorp."
        or "01   Open Name Tag Studio from Overview.\n\n02   Choose a color, font, and effect.\n\n03   Use Settings to tune tag visibility.\n\n04   RightShift toggles the menu."
    instructions.TextColor3 = Window.Theme.TextDim
    instructions.TextSize = 12
    instructions.TextWrapped = true
    instructions.TextXAlignment = Enum.TextXAlignment.Left
    instructions.TextYAlignment = Enum.TextYAlignment.Top
    instructions.Parent = guideCard

    local context = Instance.new("TextLabel")
    context.BackgroundTransparency = 1
    context.Position = UDim2.fromOffset(30, 328)
    context.Size = UDim2.new(1, -60, 0, 22)
    context.Font = Enum.Font.Gotham
    context.Text = inGameConditions() .. "   ·   " .. tostring(#game:GetService("Players"):GetPlayers()) .. " players   ·   place " .. tostring(game.PlaceId)
    context.TextColor3 = Window.Theme.AccentLight
    context.TextSize = 10
    context.TextXAlignment = Enum.TextXAlignment.Left
    context.TextTruncate = Enum.TextTruncate.AtEnd
    context.Parent = card

    local enter = Instance.new("TextButton")
    enter.AnchorPoint = Vector2.new(1, 1)
    enter.Position = UDim2.new(1, -28, 1, -22)
    enter.Size = UDim2.fromOffset(190, 42)
    enter.BackgroundColor3 = Window.Theme.Accent
    enter.BackgroundTransparency = 0.03
    enter.BorderSizePixel = 0
    enter.AutoButtonColor = false
    enter.Font = Enum.Font.GothamBold
    enter.Text = "ENTER SCORP  →"
    enter.TextColor3 = Window.Theme.TextWhite
    enter.TextSize = 13
    enter.Parent = card
    local enterCorner = Instance.new("UICorner")
    enterCorner.CornerRadius = UDim.new(0, 9)
    enterCorner.Parent = enter
    local enterScale = Instance.new("UIScale")
    enterScale.Parent = enter
    enter.MouseEnter:Connect(function()
        Window:_play("Hover")
        game:GetService("TweenService"):Create(enterScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.035 }):Play()
    end)
    enter.MouseLeave:Connect(function()
        game:GetService("TweenService"):Create(enterScale, TweenInfo.new(0.14), { Scale = 1 }):Play()
    end)

    local closed = false
    local enterInputConnection
    local function close()
        if closed then return end
        closed = true
        if enterInputConnection then pcall(function() enterInputConnection:Disconnect() end); enterInputConnection = nil end
        if not seen and type(writefile) == "function" then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder("Scorp") then makefolder("Scorp") end
                writefile("Scorp/welcome-seen.txt", "1")
            end)
        end
        Window:Toggle(true)
        Window:Notify("Welcome to Scorp", "Name Tag Studio and your community options are ready.", 4, Window.Theme.Success)
        pcall(function() gui:Destroy() end)
    end
    enter.MouseButton1Click:Connect(close)
    enterInputConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.Return and not closed then close() end
    end)

    local function refreshLocalClock()
        if closed or not context.Parent then return end
        local ok, value = pcall(inGameConditions)
        if ok and context.Parent then
            context.Text = value .. "   ·   " .. tostring(#game:GetService("Players"):GetPlayers()) .. " players   ·   place " .. tostring(game.PlaceId)
        end
    end
    task.spawn(function()
        while not closed do task.wait(15); refreshLocalClock() end
    end)
    enter.Activated:Connect(close)
    Window:OnUnload(function()
        closed = true
        if enterInputConnection then pcall(function() enterInputConnection:Disconnect() end); enterInputConnection = nil end
        pcall(function() gui:Destroy() end)
    end)
    return gui
end

function Onboarding.Start(Scorp, Window, LocalPlayer, ctx)
    local seen = false
    if type(isfile) == "function" and type(readfile) == "function" then
        pcall(function() seen = isfile("Scorp/welcome-seen.txt") and readfile("Scorp/welcome-seen.txt") == "1" end)
    end

    local splash = Scorp:CreateSplash({ Kind = "load", Theme = Window.Theme })
    splash:Play()

    task.spawn(function()
        local intro = fetchAudio(ctx, AUDIO.intro)
        if intro and splash.Gui and splash.Gui.Parent then
            local sound = Instance.new("Sound")
            sound.Name = "ScorpIntro"
            sound.SoundId = intro
            sound.Volume = 0.45
            sound.Parent = Window.Gui
            sound.Ended:Connect(function() pcall(function() sound:Destroy() end) end)
            pcall(function() sound:Play() end)
        end
    end)
    task.spawn(function()
        local hover = fetchAudio(ctx, AUDIO.hover)
        if hover and Window._sounds then
            local sound = Instance.new("Sound")
            sound.Name = "ScorpHover"
            sound.SoundId = hover
            sound.Volume = 0.25
            sound.Parent = Window.Gui
            Window._sounds.Hover = sound
        end
        local click = fetchAudio(ctx, AUDIO.click)
        if click and Window._sounds then
            local sound = Instance.new("Sound")
            sound.Name = "ScorpClick"
            sound.SoundId = click
            sound.Volume = 0.45
            sound.Parent = Window.Gui
            Window._sounds.Click = sound
        end
    end)

    task.delay(1.75, function()
        if not Window.Destroyed then buildWelcome(Scorp, Window, LocalPlayer, ctx, seen) end
    end)
end

return Onboarding
