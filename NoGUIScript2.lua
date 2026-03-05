-- =====================================================
-- Ro-Ghoul Auto Farm (Standalone, No GUI, No Settings)
-- =====================================================

local player       = game:GetService("Players").LocalPlayer
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

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
        ["Eto Yoshimura"]   = true,  -- lvl 1250+
        ["Kishou Arima"]    = true,  -- lvl 1250+
        ["Koutarou Amon"]   = true,  -- lvl 750+
        ["Touka Kirishima"] = true,  -- lvl 250+
        ["Nishiki Nishio"]  = true,  -- lvl 250+
    },

    -- Skills to use on bosses (E, F, C, R)
    Skills = { E = false, F = true, C = false, R = true },

    ReputationFarm    = true,
    ReputationCashout = true,

    -- -----------------------------------------------
    -- Boss targeting
    -- -----------------------------------------------

    -- Frames ahead to extrapolate boss movement when deciding
    -- where to snap the player and where to aim skills.
    -- Raise this (e.g. 8–12) for faster bosses like Arima / Eto.
    -- Set to 0 to disable prediction entirely.
    BossPredictFrames = 5,

    -- Force the camera to track the boss every frame.
    -- This ensures directional skills always fire toward the target
    -- rather than wherever the camera drifted to.
    CameraLockBoss = true,

    -- World-space offset from the player's root that the locked
    -- camera sits at (behind + above).
    CameraOffset = Vector3.new(0, 8, 12),
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
    ["Touka Kirishima"] = 250,
    ["Nishiki Nishio"]  = 250,
}

local skillCDs = {
    E = player.PlayerFolder.Special1CD,
    F = player.PlayerFolder.Special3CD,
    C = player.PlayerFolder.SpecialBonusCD,
    R = player.PlayerFolder.Special2CD,
}

-- =====================================================
-- getBossVelocity
-- Safely reads the boss root's linear velocity, with
-- fallbacks across different Roblox API versions.
-- =====================================================
local function getBossVelocity(root)
    local ok, vel = pcall(function() return root.AssemblyLinearVelocity end)
    if ok and vel then return vel end
    local ok2, vel2 = pcall(function() return root.Velocity end)
    if ok2 and vel2 then return vel2 end
    return Vector3.new()
end

-- =====================================================
-- predictBossPos
-- Returns where the boss root is expected to be after
-- BossPredictFrames frames, based on current velocity.
-- =====================================================
local function predictBossPos(root)
    local vel = getBossVelocity(root)
    return root.Position + vel * (config.BossPredictFrames / 60)
end

-- =====================================================
-- pressKey
--   topress – key string ("Mouse1", "E", "F", etc.)
--   aimPos  – optional Vector3; when provided, overrides
--             both the mouse-hit CFrame and the camera
--             look-direction sent to the server so that
--             all skills/attacks aim at that position.
-- =====================================================
local function pressKey(topress, aimPos)
    if not key then return end
    local remoteEvent = player.Character
        and player.Character:FindFirstChild("Remotes")
        and player.Character.Remotes:FindFirstChild("KeyEvent")
    if not remoteEvent then return end

    local hitCFrame, camCFrame
    if aimPos then
        hitCFrame = CFrame.new(aimPos)
        camCFrame = CFrame.lookAt(workspace.CurrentCamera.CFrame.Position, aimPos)
    else
        hitCFrame = player:GetMouse().Hit
        camCFrame = workspace.Camera.CFrame
    end

    remoteEvent:FireServer(key, topress, "Down", hitCFrame, nil, camCFrame)
end

-- =====================================================
-- Camera helpers
-- =====================================================
local function lockCameraToBoss(predictedPos, playerRootPos)
    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = CFrame.lookAt(playerRootPos + config.CameraOffset, predictedPos)
end

local function restoreCamera()
    workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- =====================================================
-- tp – smooth tween teleport
-- =====================================================
local function tp(pos)
    local val = Instance.new("CFrameValue")
    val.Value = player.Character.HumanoidRootPart.CFrame

    local dist  = (player.Character.HumanoidRootPart.Position - pos.p).magnitude
    local tween = TweenService:Create(
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

            -- Priority: enabled boss at or above minimum level
            if config.Boss[npc.Name]
                and tonumber(player.PlayerFolder.Stats.Level.Value) >= (bossMinLevel[npc.Name] or 0)
            then
                return npc
            end

            -- Fallback: nearest NPC in the chosen spawn category
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
-- Safety cleanup: restore camera if autofarm is toggled
-- off mid-fight
-- =====================================================
RunService.Heartbeat:Connect(function()
    if not autofarm then
        restoreCamera()
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

            local isBoss     = config.Boss[npc.Name] ~= nil and config.Boss[npc.Name] == true
            local npcChanged = false

            -- Watch in background in case NPC despawns/dies before we arrive
            coroutine.wrap(function()
                while not npcChanged do
                    if npc ~= getNPC() then npcChanged = true end
                    wait()
                end
            end)()

            -- -----------------------------------------------------------
            -- Teleport to initial attack position.
            -- For bosses: use predictBossPos so the tween destination
            -- already accounts for the boss's movement during travel.
            -- -----------------------------------------------------------
            if isBoss then
                local predictedPos = predictBossPos(npc.HumanoidRootPart)
                local predictedCF  = CFrame.new(predictedPos) * npc.HumanoidRootPart.CFrame.Rotation
                tp(predictedCF * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, config.DistanceFromBoss, 0))
            else
                tp(npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc)
            end

            npcChanged = true -- stop the watcher coroutine

            -- -----------------------------------------------------------
            -- Attack loop
            -- -----------------------------------------------------------
            while npc.Parent and npc:FindFirstChild("Head") and char.Humanoid.Health > 0 and autofarm do

                -- Re-equip if weapon was knocked off
                if not char:FindFirstChild("Kagune") and not char:FindFirstChild("Quinque") then
                    pressKey(config.Stage)
                end

                if isBoss then
                    -- -----------------------------------------------
                    -- Step 1 – Predict where boss will be next N frames
                    -- -----------------------------------------------
                    local predictedPos = predictBossPos(npc.HumanoidRootPart)

                    -- -----------------------------------------------
                    -- Step 2 – Snap player to predicted boss position.
                    -- Builds the CFrame from the extrapolated position
                    -- but preserves the original rotation technique
                    -- (90° clip-inside) that the base script relies on.
                    -- -----------------------------------------------
                    local predictedCF = CFrame.new(predictedPos) * npc.HumanoidRootPart.CFrame.Rotation
                    char.HumanoidRootPart.CFrame =
                        predictedCF * CFrame.Angles(math.rad(90), 0, 0)
                        + Vector3.new(0, config.DistanceFromBoss, 0)

                    -- -----------------------------------------------
                    -- Step 3 – Lock camera so its look direction points
                    -- at the boss; this is the direction the server uses
                    -- when resolving AoE / directional skill hits.
                    -- -----------------------------------------------
                    if config.CameraLockBoss then
                        lockCameraToBoss(predictedPos, char.HumanoidRootPart.Position)
                    end

                    -- -----------------------------------------------
                    -- Step 4 – Fire skills with aimPos = predictedPos.
                    -- pressKey passes predictedPos as both mouse.Hit
                    -- and the camera look target sent to the server,
                    -- ensuring directional skills land on the boss.
                    -- -----------------------------------------------
                    for skillKey, enabled in pairs(config.Skills) do
                        if enabled
                            and player.PlayerFolder.CanAct.Value
                            and skillCDs[skillKey].Value ~= "DownTime"
                        then
                            pressKey(skillKey, predictedPos)
                        end
                    end

                    -- -----------------------------------------------
                    -- Step 5 – Basic attack, also aimed at predicted pos
                    -- -----------------------------------------------
                    if player.PlayerFolder.CanAct.Value then
                        pressKey("Mouse1", predictedPos)
                    end

                else
                    -- Regular NPC: original behaviour unchanged
                    char.HumanoidRootPart.CFrame =
                        npc.HumanoidRootPart.CFrame + npc.HumanoidRootPart.CFrame.LookVector * config.DistanceFromNpc

                    if player.PlayerFolder.CanAct.Value then
                        pressKey("Mouse1")
                    end
                end

                task.wait()
            end

            -- -----------------------------------------------------------
            -- Post-fight cleanup
            -- -----------------------------------------------------------
            if isBoss and config.CameraLockBoss then
                restoreCamera()
            end
        end)
    end

    task.wait()
end
