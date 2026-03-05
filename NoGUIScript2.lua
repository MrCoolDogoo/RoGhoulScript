-- =====================================================
-- Ro-Ghoul Auto Farm (Standalone, No GUI, No Settings)
-- =====================================================

local player     = game:GetService("Players").LocalPlayer
local RunService = game:GetService("RunService")

repeat wait() until player:FindFirstChild("PlayerFolder")

local team    = player.PlayerFolder.Customization.Team.Value
local remotes = game:GetService("ReplicatedStorage").Remotes

-- =====================================================
-- Config (edit these directly)
-- =====================================================
local config = {
    DistanceFromNpc  = -3,
    DistanceFromBoss = -0,
    TeleportSpeed    = 150,

    -- How far the player must drift from the boss before forcing a re-snap (studs)
    BossSnapThreshold = 1,

    -- Target NPC type: "GhoulSpawns", "CCGSpawns", or "HumanSpawns"
    TargetSpawn = "GhoulSpawns",

    -- Kagune/Quinque stage to equip: "One" through "Six"
    Stage = "Two",

    -- Boss farming (set to true to farm, requires minimum level)
    Boss = {
        ["Eto Yoshimura"]   = true,  -- lvl 1250+
        ["Kishou Arima"]    = true,  -- lvl 1250+
        ["Koutarou Amon"]   = true,  -- lvl 750+
        ["Nishiki Nishio"]  = true,  -- lvl 250+
        ["Touka Kirishima"] = true,  -- lvl 250+
    },

    -- Skills to use on bosses (E, F, C, R)
    Skills = { E = false, F = false, C = false, R = false },

    ReputationFarm    = true,
    ReputationCashout = true,
}

-- =====================================================
-- State
-- =====================================================
local autofarm = false
local died     = false
local key      = nil
local oldtick  = 0

local bossMinLevel = {
    ["Eto Yoshimura"]   = 1250,
    ["Kishou Arima"]    = 1250,
    ["Koutarou Amon"]   = 750,
    ["Nishiki Nishio"]  = 250,
    ["Touka Kirishima"] = 250,
}

local skillCDs = {
    E = player.PlayerFolder.Special1CD,
    F = player.PlayerFolder.Special3CD,
    C = player.PlayerFolder.SpecialBonusCD,
    R = player.PlayerFolder.Special2CD,
}

-- =====================================================
-- Helpers
-- =====================================================
local function pressKey(topress)
    if not key then return end
    local re = player.Character
        and player.Character:FindFirstChild("Remotes")
        and player.Character.Remotes:FindFirstChild("KeyEvent")
    if re then
        re:FireServer(key, topress, "Down", player:GetMouse().Hit, nil, workspace.Camera.CFrame)
    end
end

local function tp(pos)
    local val = Instance.new("CFrameValue")
    val.Value = player.Character.HumanoidRootPart.CFrame

    local dist = (player.Character.HumanoidRootPart.Position - pos.p).magnitude
    local tween = game:GetService("TweenService"):Create(
        val,
        TweenInfo.new(dist / config.TeleportSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { Value = pos }
    )

    tween:Play()
    local done = false
    tween.Completed:Connect(function() done = true end)

    while not done do
        if not autofarm or player.Character.Humanoid.Health <= 0 then
            tween:Cancel()
            break
        end
        player.Character.HumanoidRootPart.CFrame = val.Value
        task.wait()
    end

    val:Destroy()
end

-- =====================================================
-- Boss attack CFrame helper
-- Places the player directly behind the boss using
-- LookVector so they always face it correctly.
-- =====================================================
local function getBossAttackCFrame(npcRoot)
    local offset = npcRoot.CFrame.LookVector * config.DistanceFromBoss
    return CFrame.new(npcRoot.Position + offset)
        * CFrame.Angles(0, math.atan2(-npcRoot.CFrame.LookVector.X, -npcRoot.CFrame.LookVector.Z), 0)
end

-- =====================================================
-- getNPC
-- =====================================================
local function getNPC()
    local nearest, nearestDist         = nil, math.huge
    local nearestBoss, nearestBossDist = nil, math.huge
    local playerLevel = tonumber(player.PlayerFolder.Stats.Level.Value) or 0

    for _, spawn in pairs(workspace.NPCSpawns:GetChildren()) do
        local npc = spawn:FindFirstChildOfClass("Model")
        if npc
            and npc:FindFirstChild("Head")
            and npc:FindFirstChild("HumanoidRootPart")
            and npc:FindFirstChild("Humanoid")
            and npc.Humanoid.Health > 0
            and not npc:FindFirstChild("AC")
        then
            -- Boss check: pick the nearest alive boss we are levelled for
            if config.Boss[npc.Name] == true
                and playerLevel >= (bossMinLevel[npc.Name] or 0)
            then
                local mag = (npc.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).magnitude
                if mag < nearestBossDist then
                    nearestBoss, nearestBossDist = npc, mag
                end
            end

            -- Regular NPC check
            if spawn.Name == config.TargetSpawn then
                local mag = (npc.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).magnitude
                if mag < nearestDist then
                    nearest, nearestDist = npc, mag
                end
            end
        end
    end

    -- Always prefer the nearest valid boss over regular NPCs
    return nearestBoss or nearest
end

-- =====================================================
-- getQuest
-- =====================================================
local function getQuest(getNew)
    local npc = team == "Ghoul"
        and workspace.Anteiku.Yoshimura
        or  workspace.CCGBuilding.Yoshitoki

    tp(npc.HumanoidRootPart.CFrame)
    remotes.Ally.AllyInfo:InvokeServer()
    wait()
    fireclickdetector(npc.TaskIndicator.ClickDetector)

    if autofarm and not died
        and (npc.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude <= 20
    then
        if getNew then
            remotes[npc.Name].Task:InvokeServer()
            remotes[npc.Name].Task:InvokeServer()
        else
            remotes.ReputationCashOut:InvokeServer()
            oldtick = tick()
        end
    end
end

-- =====================================================
-- Key grabber
-- =====================================================
fireclickdetector(workspace.TrainerModel.ClickIndicator.ClickDetector)
local gui = player.PlayerGui:WaitForChild("TrainersGui")
gui:WaitForChild("TrainersGuiScript")
gui:Destroy()

repeat
    for _, v in pairs(getgc(true)) do
        if not key and type(v) == "function" and getinfo(v).source:find(".ClientControl") then
            for i, c in pairs(getconstants(v)) do
                if c == "KeyEvent" then
                    local candidate = getconstant(v, i + 1)
                    if #candidate >= 100 then
                        key = candidate
                        break
                    end
                end
            end
        end
    end
    wait()
until key

-- =====================================================
-- Disable idle kick
-- =====================================================
getconnections(player.Idled)[1]:Disable()

-- =====================================================
-- Track respawns
-- =====================================================
player.CharacterAdded:Connect(function()
    died = true
end)

-- =====================================================
-- Start
-- =====================================================
autofarm = true

-- =====================================================
-- Main loop
-- =====================================================
while true do
    if autofarm then
        pcall(function()
            local char = player.Character
            if not char or char.Humanoid.Health <= 0 or not char:FindFirstChild("HumanoidRootPart") then
                died = true
                return
            end

            -- Equip weapon/kagune if not already out
            if not char:FindFirstChild("Kagune") and not char:FindFirstChild("Quinque") then
                pressKey(config.Stage)
            end

            -- Reputation quest handling
            if config.ReputationFarm
                and (not player.PlayerFolder.CurrentQuest.Complete:FindFirstChild("Aogiri Member")
                    or player.PlayerFolder.CurrentQuest.Complete["Aogiri Member"].Value
                       == player.PlayerFolder.CurrentQuest.Complete["Aogiri Member"].Max.Value)
            then
                getQuest(true)
                return
            end

            if config.ReputationCashout and tick() - oldtick > 7200 then
                getQuest(false)
            end

            -- Find target
            local npc = getNPC()
            if not npc then
                task.wait(1)
                return
            end

            local isBoss = config.Boss[npc.Name] == true
            local found  = false

            -- Watch in background in case NPC changes (dies, despawns, etc.)
            coroutine.wrap(function()
                while not found do
                    if npc ~= getNPC() then
                        found = true
                    end
                    wait()
                end
            end)()

            -- -----------------------------------------------
            -- Teleport to attack position
            -- -----------------------------------------------
            if isBoss then
                tp(getBossAttackCFrame(npc.HumanoidRootPart))
            else
                tp(npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc)
            end

            found = true -- stop the watcher coroutine

            -- -----------------------------------------------
            -- Heartbeat snap: keeps the player glued to the
            -- boss every frame so knockback can't push them off
            -- -----------------------------------------------
            local snapConnection
            if isBoss then
                snapConnection = RunService.Heartbeat:Connect(function()
                    local npcRoot  = npc and npc.Parent and npc:FindFirstChild("HumanoidRootPart")
                    local charRoot = char and char:FindFirstChild("HumanoidRootPart")
                    if not npcRoot or not charRoot then return end

                    local target = getBossAttackCFrame(npcRoot)
                    local drift  = (charRoot.Position - target.p).Magnitude

                    if drift > config.BossSnapThreshold then
                        charRoot.CFrame = target
                    end
                end)
            end

            -- -----------------------------------------------
            -- Attack loop
            -- -----------------------------------------------
            while npc.Parent
                and npc:FindFirstChild("Head")
                and npc:FindFirstChild("Humanoid")
                and npc.Humanoid.Health > 0
                and char.Humanoid.Health > 0
                and autofarm
            do
                if not char:FindFirstChild("Kagune") and not char:FindFirstChild("Quinque") then
                    pressKey(config.Stage)
                end

                if isBoss then
                    -- Fire skills if enabled and off cooldown
                    for skillKey, enabled in pairs(config.Skills) do
                        if enabled and player.PlayerFolder.CanAct.Value
                            and skillCDs[skillKey].Value ~= "DownTime"
                        then
                            pressKey(skillKey)
                        end
                    end

                    -- Hard snap every tick as secondary guarantee alongside Heartbeat
                    local npcRoot = npc:FindFirstChild("HumanoidRootPart")
                    if npcRoot then
                        char.HumanoidRootPart.CFrame = getBossAttackCFrame(npcRoot)
                    end
                else
                    char.HumanoidRootPart.CFrame =
                        npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc
                end

                if player.PlayerFolder.CanAct.Value then
                    pressKey("Mouse1")
                end

                task.wait()
            end

            -- -----------------------------------------------
            -- Cleanup after fight ends
            -- -----------------------------------------------
            if snapConnection then
                snapConnection:Disconnect()
                snapConnection = nil
            end
        end)
    end

    task.wait()
end
