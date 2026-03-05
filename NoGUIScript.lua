-- =====================================================
-- Ro-Ghoul Auto Farm (Standalone, No GUI, No Settings)
-- =====================================================

local player = game:GetService("Players").LocalPlayer

repeat wait() until player:FindFirstChild("PlayerFolder")

local team    = player.PlayerFolder.Customization.Team.Value
local remotes = game:GetService("ReplicatedStorage").Remotes

-- =====================================================
-- Config (edit these directly)
-- =====================================================
local config = {
    DistanceFromNpc  = -5,
    DistanceFromBoss = -5,
    TeleportSpeed    = 150,

    -- Target NPC type: "GhoulSpawns", "CCGSpawns", or "HumanSpawns"
    TargetSpawn = "GhoulSpawns",

    -- Kagune/Quinque stage to equip: "One" through "Six"
    Stage = "One",

    -- Boss farming (set to true to farm, requires minimum level)
    Boss = {
        ["Eto Yoshimura"] = true,  -- lvl 1250+
        ["Kishou Arima"] = true, -- lvl 1250+
        ["Koutarou Amon"] = true,  -- lvl 750+
        ["Touka Kirishima"] = true, -- lvl 250+
        ["Nishiki Nishio"] = true, -- lvl 250+
    },

    -- Skills to use on bosses (E, F, C, R)
    Skills = { E = false, F = true, C = false, R = true },

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
    ["Eto Yoshimura"] = 1250,
    ["Kishou Arima"] = 1250,
    ["Koutarou Amon"] = 750,
    ["Touka Kirishima"] = 250,
    ["Nishiki Nishio"] = 250,
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
    local remoteEvent = player.Character
        and player.Character:FindFirstChild("Remotes")
        and player.Character.Remotes:FindFirstChild("KeyEvent")
    if remoteEvent then
        remoteEvent:FireServer(key, topress, "Down", player:GetMouse().Hit, nil, workspace.Camera.CFrame)
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
-- getNPC
-- =====================================================
local function getNPC()
    local nearest, nearestDist = nil, math.huge

    for _, spawn in pairs(workspace.NPCSpawns:GetChildren()) do
        local npc = spawn:FindFirstChildOfClass("Model")
        if npc and npc:FindFirstChild("Head") and not npc:FindFirstChild("AC") then

            -- Check if it's a target boss
            if config.Boss[npc.Name]
                and tonumber(player.PlayerFolder.Stats.Level.Value) >= (bossMinLevel[npc.Name] or 0)
            then
                return npc
            end

            -- Check if it's in the chosen spawn type
            if spawn.Name == config.TargetSpawn then
                local mag = (npc.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).magnitude
                if mag < nearestDist then
                    nearest, nearestDist = npc, mag
                end
            end
        end
    end

    return nearest
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
-- Boss AI Freeze
-- =====================================================
local frozenConnections = {}

local function freezeBoss(npc)
    local humanoid = npc:FindFirstChild("Humanoid")
    local root     = npc:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    local originalWalkSpeed = humanoid.WalkSpeed
    local originalJumpPower = humanoid.JumpPower
    local frozenCFrame      = root.CFrame

    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    root.Anchored      = true
    root.CFrame        = frozenCFrame

    local active = true
    coroutine.wrap(function()
        while active and npc.Parent and humanoid.Health > 0 do
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            root.Anchored      = true
            root.CFrame        = frozenCFrame
            task.wait()
        end
    end)()

    frozenConnections[npc] = function()
        active = false
        if npc.Parent then
            humanoid.WalkSpeed = originalWalkSpeed
            humanoid.JumpPower = originalJumpPower
            root.Anchored      = false
        end
    end
end

local function unfreezeBoss(npc)
    if frozenConnections[npc] then
        frozenConnections[npc]()
        frozenConnections[npc] = nil
    end
end

-- =====================================================
-- Key grabber
-- =====================================================
fireclickdetector(workspace.TrainerModel.ClickIndicator.ClickDetector)
local trainerGui = player.PlayerGui:WaitForChild("TrainersGui")
trainerGui:WaitForChild("TrainersGuiScript")
trainerGui:Destroy()

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
-- Safety cleanup: unfreeze all bosses if autofarm stops
-- =====================================================
game:GetService("RunService").Heartbeat:Connect(function()
    if not autofarm then
        for npc in pairs(frozenConnections) do
            unfreezeBoss(npc)
        end
    end
end)

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
                and (
                    not player.PlayerFolder.CurrentQuest.Complete:FindFirstChild("Aogiri Member")
                    or player.PlayerFolder.CurrentQuest.Complete["Aogiri Member"].Value
                       == player.PlayerFolder.CurrentQuest.Complete["Aogiri Member"].Max.Value
                )
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

            local isBoss = config.Boss[npc.Name] ~= nil and config.Boss[npc.Name] == true
            local npcChanged = false

            -- Watch in background in case NPC despawns or dies before we arrive
            coroutine.wrap(function()
                while not npcChanged do
                    if npc ~= getNPC() then
                        npcChanged = true
                    end
                    wait()
                end
            end)()

            -- Teleport to attack position
            if isBoss then
                tp(npc.HumanoidRootPart.CFrame * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, config.DistanceFromBoss, 0))
                freezeBoss(npc)
            else
                tp(npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc)
            end

            npcChanged = true -- stop the watcher coroutine

            -- Attack loop
            while npc.Parent and npc:FindFirstChild("Head") and char.Humanoid.Health > 0 and autofarm do
                if not char:FindFirstChild("Kagune") and not char:FindFirstChild("Quinque") then
                    pressKey(config.Stage)
                end

                if isBoss then
                    for skillKey, enabled in pairs(config.Skills) do
                        if enabled and player.PlayerFolder.CanAct.Value
                            and skillCDs[skillKey].Value ~= "DownTime"
                        then
                            pressKey(skillKey)
                        end
                    end
                    char.HumanoidRootPart.CFrame =
                        npc.HumanoidRootPart.CFrame * CFrame.Angles(math.rad(90), 0, 0)
                        + Vector3.new(0, config.DistanceFromBoss, 0)
                else
                    char.HumanoidRootPart.CFrame =
                        npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc
                end

                if player.PlayerFolder.CanAct.Value then
                    pressKey("Mouse1")
                end

                task.wait()
            end

            -- Unfreeze boss once the fight is over
            if isBoss then
                unfreezeBoss(npc)
            end
        end)
    end

    task.wait()
end
