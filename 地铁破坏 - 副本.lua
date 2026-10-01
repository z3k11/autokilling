local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local WFE    = ReplicatedStorage:WaitForChild("WeaponFiredEvent", 15)
if not WFE then return warn("[KillUI] 找不到 WeaponFiredEvent") end

local CONFIG = {
    Enabled      = false,
    IncludeNPC   = true,
    AimCamera    = true,
    FireInterval = 0.04,
    MaxPerTick   = 4,
    LowHPFirst   = true,
    CheckTeam    = true,
    TeamMode     = "auto",
}

local logBuffer = {}
local function logMsg(s)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), s)
    print(line)
    table.insert(logBuffer, line)
    if #logBuffer > 500 then table.remove(logBuffer, 1) end
end

local capturedArgs = nil
pcall(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        if getnamecallmethod() == "FireServer" and self == WFE then
            if not capturedArgs then
                capturedArgs = table.pack(...)
                logMsg("✅ 参数已捕获 | 武器=" .. tostring(capturedArgs[1]))
            end
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
end)

local firedCount    = 0
local acceptedCount = 0
local killCount     = 0

WFE.OnClientEvent:Connect(function() acceptedCount = acceptedCount + 1 end)

pcall(function()
    local KF = ReplicatedStorage:WaitForChild("KillFeedEvent", 5)
    if KF then
        KF.OnClientEvent:Connect(function(t)
            if typeof(t) == "table" and t.AttackerName == LP.Name then
                killCount = killCount + 1
                logMsg(string.format("💀 [击杀 #%d] %s", killCount, tostring(t.VictimName)))
            end
        end)
    end
end)

local function getPlayerTeamTag(plr)
    if not plr then return nil, nil end

    if plr.Team then
        return "team:" .. plr.Team.Name, "team"
    end
    if plr.TeamColor then
        return "color:" .. tostring(plr.TeamColor.Number), "color"
    end
    local ls = plr:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            local n = v.Name:lower()
            if n:find("team") or n:find("side") or n:find("faction")
               or n:find("阵营") or n:find("队伍") then
                return "ls:" .. tostring(v.Value), "ls"
            end
        end
    end
    for name, value in pairs(plr:GetAttributes()) do
        local n = name:lower()
        if n:find("team") or n:find("side") or n:find("faction") then
            return "attr:" .. tostring(value), "attr"
        end
    end
    local char = plr.Character
    if char then
        for name, value in pairs(char:GetAttributes()) do
            local n = name:lower()
            if n:find("team") or n:find("side") or n:find("faction") then
                return "cattr:" .. tostring(value), "cattr"
            end
        end
        local tv = char:FindFirstChild("Team")
        if tv then
            if tv:IsA("StringValue") then return "cs:" .. tv.Value, "cs" end
            if tv:IsA("ObjectValue") and tv.Value then return "co:" .. tv.Value.Name, "co" end
        end
    end
    if char then
        local head = char:FindFirstChild("Head")
        if head then
            return "head:" .. tostring(head.Color), "head"
        end
    end
    return nil, nil
end

local function getNpcTeamTag(npc)
    if not npc then return nil, nil end

    local tv = npc:FindFirstChild("Team")
    if tv then
        if tv:IsA("StringValue") then return "team:" .. tv.Value, "team" end
        if tv:IsA("ObjectValue") and tv.Value then return "team:" .. tv.Value.Name, "team" end
    end
    for name, value in pairs(npc:GetAttributes()) do
        local n = name:lower()
        if n:find("team") or n:find("side") or n:find("faction") then
            return "attr:" .. tostring(value), "attr"
        end
    end
    local head = npc:FindFirstChild("Head")
    if head then
        return "head:" .. tostring(head.Color), "head"
    end
    return nil, nil
end

local function isEnemy(targetChar)
    if not CONFIG.CheckTeam then return true end
    if not targetChar then return false end

    local myTag, mySource = getPlayerTeamTag(LP)
    if not myTag then
        return true
    end

    local plr = Players:GetPlayerFromCharacter(targetChar)
    if plr then
        local otherTag, otherSource = getPlayerTeamTag(plr)
        if not otherTag then return true end
        if mySource == otherSource then
            return myTag ~= otherTag
        end
        return true
    end

    local npcTag, npcSource = getNpcTeamTag(targetChar)
    if not npcTag then return true end
    if mySource == npcSource then
        return myTag ~= npcTag
    end
    local myVal = myTag:match(":(.+)$") or myTag
    local npcVal = npcTag:match(":(.+)$") or npcTag
    return myVal ~= npcVal
end

local function debugTeams()
    print("════════ 阵营调试 ════════")
    print(string.format("我: %s", LP.Name))
    print(string.format("  Team: %s", tostring(LP.Team)))
    print(string.format("  TeamColor: %s", tostring(LP.TeamColor)))
    local tag, src = getPlayerTeamTag(LP)
    print(string.format("  → 识别 tag: %s  (来源: %s)", tostring(tag), tostring(src)))

    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        print("  leaderstats:")
        for _, v in ipairs(ls:GetChildren()) do
            print("    " .. v.Name .. " = " .. tostring(v.Value))
        end
    end

    print("──────── 玩家 ────────")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local t, s = getPlayerTeamTag(plr)
            local isE = isEnemy(plr.Character)
            print(string.format(
                "%-20s | Tag=%-20s src=%-6s | %s",
                plr.Name, tostring(t), tostring(s), isE and "敌" or "友"))
        end
    end

    print("──────── NPC (前 8) ────────")
    local npcs = workspace:FindFirstChild("NPCs")
    if npcs then
        local i = 0
        for _, npc in ipairs(npcs:GetChildren()) do
            if i >= 8 then break end
            local t, s = getNpcTeamTag(npc)
            local isE = isEnemy(npc)
            print(string.format(
                "%-20s | Tag=%-20s src=%-6s | %s",
                npc.Name, tostring(t), tostring(s), isE and "敌" or "友"))
            i = i + 1
        end
    end
    print("════════════════════════")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function collectTargets()
    local list = {}
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return list end
    local myPos = myRoot.Position

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 then
                if isEnemy(plr.Character) then
                    table.insert(list, {
                        char = plr.Character, name = plr.Name, hp = hum.Health,
                        dist = (root.Position - myPos).Magnitude, isNpc = false,
                    })
                end
            end
        end
    end

    if CONFIG.IncludeNPC then
        local npcs = workspace:FindFirstChild("NPCs")
        if npcs then
            for _, npc in ipairs(npcs:GetChildren()) do
                local hum = npc:FindFirstChildOfClass("Humanoid")
                local root = npc:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    if isEnemy(npc) then
                        table.insert(list, {
                            char = npc, name = npc.Name, hp = hum.Health,
                            dist = (root.Position - myPos).Magnitude, isNpc = true,
                        })
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if CONFIG.LowHPFirst and math.abs(a.hp - b.hp) > 20 then
            return a.hp < b.hp
        end
        return a.dist < b.dist
    end)
    return list
end

local function getCurrentWeapon()
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then return t.Name end
        end
    end
    return capturedArgs and capturedArgs[1] or "M16"
end

local function tryFire(target)
    if not capturedArgs then return false end
    local char = target.char
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not head then return false end

    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false end

    local origin = myRoot.Position + Vector3.new(0, 1.5, 0)

    local toTarget = head.Position - origin
    if toTarget.Magnitude < 2 then return false end
    local d = toTarget.Magnitude
    local dir = toTarget.Unit

    rayParams.FilterDescendantsInstances = {LP.Character}
    local vis = workspace:Raycast(origin, dir * (d - 1.5), rayParams)
    if vis then return false end

    local r = workspace:Raycast(origin, dir * (d + 1), rayParams)
    if not r then return false end

    if CONFIG.AimCamera and Camera then
        local lookDir = head.Position - Camera.CFrame.Position
        if lookDir.Magnitude > 0.1 then
            local newCF = CFrame.lookAt(Camera.CFrame.Position, Camera.CFrame.Position + lookDir.Unit)
            Camera.CFrame = Camera.CFrame:Lerp(newCF, 0.5)
        end
    end

    local args = {}
    for i = 1, capturedArgs.n do args[i] = capturedArgs[i] end
    args[1] = getCurrentWeapon()
    args[2] = origin
    args[3] = dir
    args[4] = r.Instance
    args[5] = r.Position
    args[6] = r.Normal
    args[7] = r.Material.Name

    WFE:FireServer(table.unpack(args, 1, capturedArgs.n))
    firedCount = firedCount + 1
    return true
end

local lastFire = 0
RunService.Heartbeat:Connect(function()
    if not CONFIG.Enabled or not capturedArgs then return end
    local now = os.clock()
    if now - lastFire < CONFIG.FireInterval then return end
    lastFire = now

    local targets = collectTargets()
    if #targets == 0 then return end

    local fired = 0
    for _, t in ipairs(targets) do
        if fired >= CONFIG.MaxPerTick then break end
        if tryFire(t) then fired = fired + 1 end
    end
end)

local COLORS = {
    bg        = Color3.fromRGB(18, 18, 24),
    bgTop     = Color3.fromRGB(28, 28, 38),
    card      = Color3.fromRGB(32, 32, 42),
    cardHover = Color3.fromRGB(38, 38, 50),
    accent    = Color3.fromRGB(80, 200, 255),
    danger    = Color3.fromRGB(220, 60, 80),
    success   = Color3.fromRGB(80, 220, 140),
    warn      = Color3.fromRGB(255, 180, 60),
    text      = Color3.fromRGB(230, 235, 245),
    textDim   = Color3.fromRGB(140, 150, 170),
}

local gui = Instance.new("ScreenGui")
gui.Name = "KillUIv19"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 350, 0, 470)
main.Position = UDim2.new(0, 100, 0, 80)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = COLORS.accent
mainStroke.Thickness = 1.5
mainStroke.Transparency = 0.5

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 36)
topBar.BackgroundColor3 = COLORS.bgTop
topBar.BorderSizePixel = 0
topBar.Parent = main
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 12)

local topPatch = Instance.new("Frame")
topPatch.Size = UDim2.new(1, 0, 0, 10)
topPatch.Position = UDim2.new(0, 0, 1, -10)
topPatch.BackgroundColor3 = COLORS.bgTop
topPatch.BorderSizePixel = 0
topPatch.Parent = topBar

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(0, 14, 0.5, -4)
statusDot.BackgroundColor3 = COLORS.textDim
statusDot.BorderSizePixel = 0
statusDot.Parent = topBar
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

local statusDotStroke = Instance.new("UIStroke", statusDot)
statusDotStroke.Color = COLORS.textDim
statusDotStroke.Thickness = 1
statusDotStroke.Transparency = 0.5

local title = Instance.new("TextLabel")
title.Text = "击杀助手 v19"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = COLORS.text
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.new(0, 30, 0, 0)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local collapseBtn = Instance.new("TextButton")
collapseBtn.Text = "—"
collapseBtn.Font = Enum.Font.GothamBold
collapseBtn.TextSize = 16
collapseBtn.TextColor3 = COLORS.textDim
collapseBtn.BackgroundColor3 = COLORS.card
collapseBtn.BorderSizePixel = 0
collapseBtn.AutoButtonColor = false
collapseBtn.Size = UDim2.new(0, 24, 0, 24)
collapseBtn.Position = UDim2.new(1, -30, 0.5, -12)
collapseBtn.Parent = topBar
Instance.new("UICorner", collapseBtn).CornerRadius = UDim.new(0, 6)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -36)
content.Position = UDim2.new(0, 0, 0, 36)
content.BackgroundTransparency = 1
content.Parent = main

local contentLayout = Instance.new("UIListLayout", content)
contentLayout.Padding = UDim.new(0, 8)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder

local contentPad = Instance.new("UIPadding", content)
contentPad.PaddingTop = UDim.new(0, 4)
contentPad.PaddingBottom = UDim.new(0, 12)
contentPad.PaddingLeft = UDim.new(0, 12)
contentPad.PaddingRight = UDim.new(0, 12)

local mainBtn = Instance.new("TextButton")
mainBtn.Text = "⚡  启动击杀"
mainBtn.Font = Enum.Font.GothamBold
mainBtn.TextSize = 15
mainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
mainBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 70)
mainBtn.BorderSizePixel = 0
mainBtn.AutoButtonColor = false
mainBtn.Size = UDim2.new(1, 0, 0, 46)
mainBtn.LayoutOrder = 1
mainBtn.Parent = content
Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, 8)

local mainBtnStroke = Instance.new("UIStroke", mainBtn)
mainBtnStroke.Color = Color3.fromRGB(120, 220, 160)
mainBtnStroke.Thickness = 1
mainBtnStroke.Transparency = 0.5

local statusCard = Instance.new("Frame")
statusCard.Size = UDim2.new(1, 0, 0, 70)
statusCard.BackgroundColor3 = COLORS.card
statusCard.BorderSizePixel = 0
statusCard.LayoutOrder = 2
statusCard.Parent = content
Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 8)

local statusText = Instance.new("TextLabel")
statusText.Text = "等待捕获参数\n请先手动开一枪"
statusText.Font = Enum.Font.Code
statusText.TextSize = 11
statusText.TextColor3 = COLORS.textDim
statusText.BackgroundTransparency = 1
statusText.Size = UDim2.new(1, -16, 1, 0)
statusText.Position = UDim2.new(0, 8, 0, 0)
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.TextYAlignment = Enum.TextYAlignment.Center
statusText.Parent = statusCard

local function makeSection(titleText, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 18)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = content

    local lbl = Instance.new("TextLabel")
    lbl.Text = titleText
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextColor3 = COLORS.textDim
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -80, 0, 1)
    line.Position = UDim2.new(0, 80, 0.5, 0)
    line.BackgroundColor3 = COLORS.textDim
    line.BackgroundTransparency = 0.7
    line.BorderSizePixel = 0
    line.Parent = row

    return row
end

local function makeRow(order, labelText, valueText, isToggle, initialOn)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundColor3 = COLORS.card
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = content
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Text = labelText
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = COLORS.text
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(0.55, 0, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local valueBtn = Instance.new("TextButton")
    valueBtn.Text = valueText
    valueBtn.Font = Enum.Font.GothamBold
    valueBtn.TextSize = 11
    valueBtn.TextColor3 = COLORS.text
    valueBtn.BackgroundColor3 = isToggle and (initialOn and COLORS.success or COLORS.cardHover) or COLORS.cardHover
    valueBtn.BorderSizePixel = 0
    valueBtn.AutoButtonColor = false
    valueBtn.Size = UDim2.new(0, 90, 0, 22)
    valueBtn.Position = UDim2.new(1, -102, 0.5, -11)
    valueBtn.Parent = row
    Instance.new("UICorner", valueBtn).CornerRadius = UDim.new(0, 6)

    return valueBtn, row
end

makeSection("──  设置  ──", 3)

local aimRow  = makeRow(4, "自动朝向目标", "开", true, true)
local speedRow = makeRow(5, "射击频率", "0.04s", false)
local maxRow  = makeRow(6, "每帧最多", "4 个", false)
local npcRow  = makeRow(7, "NPC 击杀", "开", true, true)
local teamRow = makeRow(8, "阵营检测", "开", true, true)

local debugBtn = Instance.new("TextButton")
debugBtn.Text = "🔍  阵营调试（打印到控制台）"
debugBtn.Font = Enum.Font.GothamBold
debugBtn.TextSize = 12
debugBtn.TextColor3 = Color3.fromRGB(255, 230, 180)
debugBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 30)
debugBtn.BorderSizePixel = 0
debugBtn.AutoButtonColor = false
debugBtn.Size = UDim2.new(1, 0, 0, 32)
debugBtn.LayoutOrder = 9
debugBtn.Parent = content
Instance.new("UICorner", debugBtn).CornerRadius = UDim.new(0, 8)

local debugBtnStroke = Instance.new("UIStroke", debugBtn)
debugBtnStroke.Color = Color3.fromRGB(255, 200, 100)
debugBtnStroke.Thickness = 1
debugBtnStroke.Transparency = 0.5

local dumpBtn = Instance.new("TextButton")
dumpBtn.Text = "导出日志到剪贴板"
dumpBtn.Font = Enum.Font.Gotham
dumpBtn.TextSize = 12
dumpBtn.TextColor3 = COLORS.text
dumpBtn.BackgroundColor3 = COLORS.card
dumpBtn.BorderSizePixel = 0
dumpBtn.AutoButtonColor = false
dumpBtn.Size = UDim2.new(1, 0, 0, 32)
dumpBtn.LayoutOrder = 10
dumpBtn.Parent = content
Instance.new("UICorner", dumpBtn).CornerRadius = UDim.new(0, 8)

local dragging, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local expandedSize  = UDim2.new(0, 350, 0, 470)
local collapsedSize = UDim2.new(0, 350, 0, 36)
local collapsed = false
collapseBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    if collapsed then
        content.Visible = false; collapseBtn.Text = "+"
        TweenService:Create(main, TweenInfo.new(0.18), {Size = collapsedSize}):Play()
    else
        content.Visible = true; collapseBtn.Text = "—"
        TweenService:Create(main, TweenInfo.new(0.18), {Size = expandedSize}):Play()
    end
end)

mainBtn.MouseButton1Click:Connect(function()
    CONFIG.Enabled = not CONFIG.Enabled
    if CONFIG.Enabled then
        mainBtn.Text = "■  停止击杀"
        mainBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 55)
        mainBtnStroke.Color = Color3.fromRGB(255, 120, 140)
        firedCount = 0; acceptedCount = 0; killCount = 0
        logMsg("⚡ 击杀 已开启")
    else
        mainBtn.Text = "⚡  启动击杀"
        mainBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 70)
        mainBtnStroke.Color = Color3.fromRGB(120, 220, 160)
        logMsg("⚡ 击杀 已关闭")
    end
end)

aimRow.MouseButton1Click:Connect(function()
    CONFIG.AimCamera = not CONFIG.AimCamera
    aimRow.Text = CONFIG.AimCamera and "开" or "关"
    aimRow.BackgroundColor3 = CONFIG.AimCamera and COLORS.success or COLORS.cardHover
end)

local speeds = {{v=0.02,label="0.02s"}, {v=0.04,label="0.04s"}, {v=0.06,label="0.06s"}, {v=0.10,label="0.10s"}, {v=0.20,label="0.20s"}}
local speedIdx = 2
CONFIG.FireInterval = speeds[speedIdx].v
speedRow.MouseButton1Click:Connect(function()
    speedIdx = speedIdx % #speeds + 1
    CONFIG.FireInterval = speeds[speedIdx].v
    speedRow.Text = speeds[speedIdx].label
end)

local maxes = {1, 2, 4, 6, 10}
local maxIdx = 3
CONFIG.MaxPerTick = maxes[maxIdx]
maxRow.MouseButton1Click:Connect(function()
    maxIdx = maxIdx % #maxes + 1
    CONFIG.MaxPerTick = maxes[maxIdx]
    maxRow.Text = CONFIG.MaxPerTick .. " 个"
end)

npcRow.MouseButton1Click:Connect(function()
    CONFIG.IncludeNPC = not CONFIG.IncludeNPC
    npcRow.Text = CONFIG.IncludeNPC and "开" or "关"
    npcRow.BackgroundColor3 = CONFIG.IncludeNPC and COLORS.success or COLORS.cardHover
end)

teamRow.MouseButton1Click:Connect(function()
    CONFIG.CheckTeam = not CONFIG.CheckTeam
    teamRow.Text = CONFIG.CheckTeam and "开" or "关"
    teamRow.BackgroundColor3 = CONFIG.CheckTeam and COLORS.success or COLORS.cardHover
end)

debugBtn.MouseButton1Click:Connect(function()
    debugTeams()
    logMsg("🔍 已输出阵营调试信息到控制台")
end)

dumpBtn.MouseButton1Click:Connect(function()
    local text = table.concat(logBuffer, "\n")
    if setclipboard then
        pcall(function() setclipboard(text) end); logMsg("📋 已复制 "..#logBuffer.." 行")
    elseif toclipboard then
        pcall(function() toclipboard(text) end); logMsg("📋 已复制 "..#logBuffer.." 行")
    end
end)

RunService.Heartbeat:Connect(function()
    if capturedArgs then
        local targets = collectTargets()

        local myTag, mySrc = getPlayerTeamTag(LP)

        statusText.Text = string.format(
            "开火 %d | 击杀 %d | 回执 %d\n目标 %d 个\n我=%s (%s)",
            firedCount, killCount, acceptedCount, #targets,
            tostring(myTag or "?"), tostring(mySrc or "?"))
        statusText.TextColor3 = COLORS.text

        if CONFIG.Enabled then
            statusDot.BackgroundColor3 = COLORS.danger
            statusDotStroke.Color = COLORS.danger
        else
            statusDot.BackgroundColor3 = COLORS.success
            statusDotStroke.Color = COLORS.success
        end
    else
        statusText.Text = "等待捕获参数\n请先手动开一枪"
        statusText.TextColor3 = COLORS.textDim
        statusDot.BackgroundColor3 = COLORS.warn
        statusDotStroke.Color = COLORS.warn
    end
end)