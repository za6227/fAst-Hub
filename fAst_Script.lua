-- // ======================================================== // --
-- //   fAst Hub V10 - Relentless Combo Boss Engine            // --
-- //   Reversed & Authored by cook45                          // --
-- // ======================================================== // --

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local guiParent = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

-- 1. ล้าง Hook, ลูป และ GUI เก่าออกทั้งหมด
if getgenv()._JackLoop then pcall(function() getgenv()._JackLoop:Disconnect() end) getgenv()._JackLoop = nil end
if getgenv()._fAstLoop then pcall(function() getgenv()._fAstLoop:Disconnect() end) getgenv()._fAstLoop = nil end
if getgenv()._BossCombatLoop then pcall(function() getgenv()._BossCombatLoop:Disconnect() end) getgenv()._BossCombatLoop = nil end
if getgenv()._fAstInputConn then pcall(function() getgenv()._fAstInputConn:Disconnect() end) getgenv()._fAstInputConn = nil end

getgenv().DG_AutoParry = nil
getgenv().BossBot = nil
getgenv().JackCombat = nil

if guiParent:FindFirstChild("fAstHub_DG") then guiParent.fAstHub_DG:Destroy() end
if guiParent:FindFirstChild("fAstToastGui") then guiParent.fAstToastGui:Destroy() end

-- 2. ระบบ Auto-Run อัตโนมัติเมื่อย้ายห้อง / วาร์ปเข้าห้องดวล (Queue On Teleport)
local queue_on_teleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
if queue_on_teleport and not getgenv()._fAstTeleportHooked then
    getgenv()._fAstTeleportHooked = true
    LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started then
            pcall(function()
                queue_on_teleport([[
                    task.wait(1.5)
                    loadstring(readfile("fAstHub_DG.lua"))()
                ]])
            end)
        end
    end)
end

pcall(function()
    if writefile then
        writefile("fAstHub_DG.lua", readfile and readfile("fAstHub_DG.lua") or "")
    end
end)

-- 3. ฟังก์ชันออริจินัลแท้ๆ จาก BaseActionManager (ไม่ซ้อน Hook)
local BaseActionManager = require(ReplicatedStorage.Modules.BaseActionManager)
local CleanOriginalCompute = BaseActionManager._computeImpactResolution

local GameManager = require(ReplicatedStorage:WaitForChild("GameManager"))
local CharacterController = GameManager:GetController("CharacterController")

-- รายการบอสที่สามารถเลือกสู้ได้
local BossList = {
    {Id = "Any", Display = "Auto (Any)"},
    {Id = "Jack", Display = "Jack"},
    {Id = "Silene", Display = "Silene"},
    {Id = "Benkei", Display = "Benkei"},
    {Id = "NephraAmmut", Display = "Nephra & Ammut"},
    {Id = "Tremor", Display = "Tremor"}
}

local currentBossIndex = 2 -- Default to Jack

-- // 4. CONFIG // --
local oldCfg = getgenv().fAstConfig or {}
getgenv().fAstConfig = {
    AutoParry = false,
    ParryKeybind = oldCfg.ParryKeybind or Enum.KeyCode.V,
    AutoBoss = false,
    AutoReturnLobby = false,
    AutoClaimRewards = false,
    SelectedBoss = oldCfg.SelectedBoss or "Jack",
    SelectedBossId = oldCfg.SelectedBossId or "Jack"
}

-- ค้นหา index ปัจจุบันจาก config
for idx, b in ipairs(BossList) do
    if b.Display == getgenv().fAstConfig.SelectedBoss or b.Id == getgenv().fAstConfig.SelectedBossId then
        currentBossIndex = idx
        break
    end
end

-- HUD Toast Notification
local function ShowHUDToast(text, color)
    local sg = guiParent:FindFirstChild("fAstToastGui") or Instance.new("ScreenGui")
    sg.Name = "fAstToastGui"
    sg.ResetOnSpawn = false
    sg.Parent = guiParent

    local oldToast = sg:FindFirstChild("Toast")
    if oldToast then oldToast:Destroy() end

    local Toast = Instance.new("Frame")
    Toast.Name = "Toast"
    Toast.Size = UDim2.new(0, 210, 0, 36)
    Toast.Position = UDim2.new(0.5, -105, 0.15, 0)
    Toast.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    Toast.BorderSizePixel = 0
    Toast.Parent = sg

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 8)
    tc.Parent = Toast

    local ts = Instance.new("UIStroke")
    ts.Thickness = 1.5
    ts.Color = color or Color3.fromRGB(140, 60, 255)
    ts.Parent = Toast

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Font = Enum.Font.GothamBold
    tl.Text = text
    tl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    tl.TextSize = 13
    tl.Parent = Toast

    task.delay(1.2, function()
        if Toast and Toast.Parent then
            TweenService:Create(Toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
            TweenService:Create(tl, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
            task.wait(0.2)
            Toast:Destroy()
        end
    end)
end

-- // 5. IMMUNITY HOOK: ป้องกันไฟและสกิลพื้นของบอสทุกตัว 100% // --
local function HookAllBossHazards()
    local mb = ReplicatedStorage:FindFirstChild("MiniBossKits")
    if not mb then return end
    for _, bossKit in ipairs(mb:GetChildren()) do
        local hz = bossKit:FindFirstChild("Hazards")
        if hz then
            for _, hazard in ipairs(hz:GetChildren()) do
                local clientMod = hazard:FindFirstChild("Client")
                if clientMod and clientMod:IsA("ModuleScript") then
                    pcall(function()
                        local mod = require(clientMod)
                        if type(mod) == "table" and type(mod.touches) == "function" then
                            mod.touches = function() return false end
                        end
                    end)
                end
            end
        end
    end
end
HookAllBossHazards()

-- // 5.1 SILENT AIM / 100% HIT REGISTRATION HOOK (ตีโดนทุกครั้ง 100%) // --
-- เมื่อเซิร์ฟเวอร์ขอเช็คตำแหน่ง Hitbox การฟัน (RequestHitboxOnImpact)
-- เราจะส่งพิกัด CFrame ที่จ่อหน้าบอส 2.5 studs ตรงจุดตายพอดี ทำให้ทุกการโจมตีของผู้เล่นโดน 100%
local RequestHitboxOnImpact = ReplicatedStorage.Remotes.PlayerCharacter.Request:WaitForChild("RequestHitboxOnImpact")

local function GetPerfectStrikeCFrame(origCF)
    if not getgenv().fAstConfig or not getgenv().fAstConfig.AutoBoss then
        return origCF
    end
    local targetBoss = FindBossTarget(getgenv().fAstConfig.SelectedBoss)
    if targetBoss and IsBossAlive(targetBoss) then
        local bRoot = targetBoss:FindFirstChild("HumanoidRootPart")
        if bRoot then
            local toB = (bRoot.Position - origCF.Position)
            local flatToB = Vector3.new(toB.X, 0, toB.Z)
            local flatUnit = flatToB.Magnitude > 0.1 and flatToB.Unit or origCF.LookVector
            -- ปรับระดับความสูงและตำแหน่งให้อยู่ด้านหน้าบอส 2.4 studs ที่ระดับบอสพอดี ทำให้ Hitbox โดน 100%
            local strikePos = Vector3.new(bRoot.Position.X - flatUnit.X * 2.4, bRoot.Position.Y, bRoot.Position.Z - flatUnit.Z * 2.4)
            return CFrame.lookAt(strikePos, bRoot.Position)
        end
    end
    return origCF
end

if not getgenv()._HitboxFuncHooked and type(hookfunction) == "function" then
    getgenv()._HitboxFuncHooked = true
    local oldHitboxFire
    pcall(function()
        oldHitboxFire = hookfunction(RequestHitboxOnImpact.FireServer, function(self, cf, t, id)
            cf = GetPerfectStrikeCFrame(cf)
            return oldHitboxFire(self, cf, t, id)
        end)
    end)
end

if not getgenv()._HitboxNamecallHooked and type(hookmetamethod) == "function" then
    getgenv()._HitboxNamecallHooked = true
    local rawNamecall
    rawNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if self == RequestHitboxOnImpact and (method == "FireServer" or method == "fireServer") then
            local args = {...}
            args[1] = GetPerfectStrikeCFrame(args[1])
            return rawNamecall(self, table.unpack(args))
        end
        return rawNamecall(self, ...)
    end)
end

-- เช็คสกิลอันติของคู่ต่อสู้ใน PVP
local function IsUltimateAttack(impactData)
    if not impactData then return false end
    if impactData.triggerUltimate or impactData.unparryable then
        return true
    end
    if impactData.sourceModule then
        local modName = impactData.sourceModule.Name
        local fullName = impactData.sourceModule:GetFullName()
        if string.find(modName, "Ultimate") or string.find(fullName, "Ultimate") then
            return true
        end
    end
    if impactData.impactResults and impactData.impactResults.GetHit then
        if impactData.impactResults.GetHit.triggerUltimate then
            return true
        end
    end
    return false
end

-- ตรวจสอบว่าบอสยังมีชีวิตอยู่จริงหรือไม่ (ตรวจทั้ง Attribute Health และ Humanoid)
local function IsBossAlive(model)
    if not model or not model.Parent then return false end

    -- บอสใน Dueling Grounds เลือดจริงจะอยู่ที่ Attribute "Health" (ไม่ใช่ Humanoid.Health)
    local attrHealth = model:GetAttribute("Health")
    if attrHealth ~= nil and attrHealth <= 0 then
        return false
    end

    local npcHealth = model:GetAttribute("NPCHealth")
    if npcHealth ~= nil and npcHealth <= 0 then
        return false
    end

    if model:GetAttribute("Dead") == true or model:GetAttribute("IsDead") == true then
        return false
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then
        return false
    end

    return true
end

-- ค้นหา Model บอสตามที่ผู้ใช้เลือก (รองรับทั้งชื่อตรงและ MiniBoss_xxx)
local function FindBossTarget(chosenBoss)
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local candidates = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= char and obj.Name ~= "Player_Client" then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local root = obj:FindFirstChild("HumanoidRootPart")
            if hum and root and IsBossAlive(obj) then
                local plr = Players:GetPlayerFromCharacter(obj)
                if not plr then
                    table.insert(candidates, obj)
                end
            end
        end
    end

    if #candidates == 0 then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj ~= char and obj.Name ~= "Player_Client" then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = obj:FindFirstChild("HumanoidRootPart")
                if hum and root and IsBossAlive(obj) and (root.Position - myRoot.Position).Magnitude < 180 then
                    local plr = Players:GetPlayerFromCharacter(obj)
                    if not plr then
                        table.insert(candidates, obj)
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    if chosenBoss and chosenBoss ~= "Auto (Any)" then
        local cLower = string.lower(chosenBoss)
        for _, m in ipairs(candidates) do
            local nLower = string.lower(m.Name)
            if string.find(nLower, cLower) or (chosenBoss == "Nephra & Ammut" and (string.find(nLower, "nephra") or string.find(nLower, "ammut"))) then
                return m
            end
        end
    end

    table.sort(candidates, function(a, b)
        local ra = a:FindFirstChild("HumanoidRootPart")
        local rb = b:FindFirstChild("HumanoidRootPart")
        if ra and rb then
            return (ra.Position - myRoot.Position).Magnitude < (rb.Position - myRoot.Position).Magnitude
        end
        return false
    end)
    return candidates[1]
end

-- // 6. HOOK DEFENSE ENGINE // --
local function ApplyCleanHook(char)
    task.spawn(function()
        local handler = nil
        for _ = 1, 60 do
            handler = CharacterController:GetCharacterHandler(char)
            if handler and handler.ActionManager then break end
            task.wait(0.1)
        end
        if not handler or not handler.ActionManager then return end

        local am = handler.ActionManager

        am._computeImpactResolution = function(self, impactData)
            local isFromBoss = false
            if impactData.attackerCharacter then
                local plr = Players:GetPlayerFromCharacter(impactData.attackerCharacter)
                if not plr then isFromBoss = true end
            end

            -- ถ้าโดนโจมตีจากบอสและเปิด AutoBoss -> Parry 100%
            if isFromBoss and getgenv().fAstConfig and getgenv().fAstConfig.AutoBoss then
                local oldP = handler.IsParrying
                handler.IsParrying = true
                local res = CleanOriginalCompute(self, impactData)
                handler.IsParrying = oldP
                return res
            end

            -- ถ้าเป็นการเล่นใน PVP ทั่วไป (AutoParry)
            if not getgenv().fAstConfig or not getgenv().fAstConfig.AutoParry then
                return CleanOriginalCompute(self, impactData)
            end

            -- ไม่กันอันติของทีมตรงข้ามใน PVP
            if IsUltimateAttack(impactData) then
                return CleanOriginalCompute(self, impactData)
            end

            local oldP = handler.IsParrying
            handler.IsParrying = true
            local res = CleanOriginalCompute(self, impactData)
            handler.IsParrying = oldP

            return res
        end
    end)
end

if LocalPlayer.Character then ApplyCleanHook(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(ApplyCleanHook)

-- // 7. AUTO RETURN TO LOBBY // --
local isReturningLobby = false

local function TriggerAutoReturnToLobby(reason)
    if not getgenv().fAstConfig or not getgenv().fAstConfig.AutoReturnLobby then return end
    if isReturningLobby then return end
    isReturningLobby = true

    task.spawn(function()
        ShowHUDToast("🏆 บอสตายแล้ว! กำลังกลับล็อบบี้อัตโนมัติ...", Color3.fromRGB(50, 255, 150))
        -- รอ 1.5 วินาที เพื่อให้เซิร์ฟเวอร์สรุปผลและบันทึกของรางวัล (Souls, Gems, Relic Keys)
        task.wait(1.5)

        for attempt = 1, 8 do
            -- 1. ยิง Remote ออกจากสนามมินิบอส (MiniBossFight.Request_Leave)
            pcall(function()
                local mb = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("MiniBossFight")
                if mb and mb:FindFirstChild("Request_Leave") then
                    mb.Request_Leave:FireServer()
                end
            end)

            -- 2. กดปุ่ม ReturnButton บน MiniBossResultsGui
            pcall(function()
                local pgui = LocalPlayer:FindFirstChild("PlayerGui")
                local rGui = pgui and pgui:FindFirstChild("MiniBossResultsGui")
                if rGui and rGui.Enabled then
                    local btn = rGui.Screen.Stage:FindFirstChild("ReturnButton")
                    if btn and getconnections then
                        for _, c in ipairs(getconnections(btn.Activated)) do
                            c:Fire()
                        end
                    end
                end
            end)

            -- 3. ยิง Match RequestReturnToLobby สำรองกรณีเป็นสนามปกติ
            pcall(function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                if remotes and remotes:FindFirstChild("Match") and remotes.Match:FindFirstChild("RequestReturnToLobby") then
                    remotes.Match.RequestReturnToLobby:FireServer()
                end
            end)

            task.wait(0.8)
        end
    end)
end

-- ดักจับสัญญาณบอสแพ้จากเซิร์ฟเวอร์โดยตรง
pcall(function()
    local mb = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("MiniBossFight")
    if mb then
        if mb:FindFirstChild("Banner") then
            mb.Banner.OnClientEvent:Connect(function(matchId, bannerType)
                if bannerType == "Victory" then
                    TriggerAutoReturnToLobby("BannerVictory")
                end
            end)
        end
        if mb:FindFirstChild("Result") then
            mb.Result.OnClientEvent:Connect(function()
                TriggerAutoReturnToLobby("MiniBossResult")
            end)
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    isReturningLobby = false
end)

-- // 7.6 AUTO CLAIM REWARDS ENGINE // --
local function ClaimAllRewards(silent)
    task.spawn(function()
        -- 1. เคลมรางวัล Like (+500 Coins +50 Gems)
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Player")
            if remotes and remotes:FindFirstChild("RequestLikesReward") then
                remotes.RequestLikesReward:FireServer()
            end
        end)

        -- 2. เคลมรางวัล Favorite (+1,000 Coins +75 Gems)
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Player")
            if remotes and remotes:FindFirstChild("RequestFavoriteReward") then
                remotes.RequestFavoriteReward:FireServer()
            end
        end)

        -- 3. เคลมรางวัล BattlePass อัตโนมัติ
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BattlePass")
            if remotes and remotes:FindFirstChild("Request_Claim") then
                remotes.Request_Claim:FireServer()
            end
        end)

        -- 4. เคลม EventProgress / Keepsake
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("EventProgress")
            if remotes and remotes:FindFirstChild("Request_RedeemKey") then
                remotes.Request_RedeemKey:FireServer()
            end
        end)

        if not silent then
            ShowHUDToast("🎁 ส่งคำขอรับรางวัลทั้งหมดเรียบร้อย!", Color3.fromRGB(255, 100, 200))
        end
    end)
end

-- ลูปตรวจสอบเคลมรางวัลอัตโนมัติเบื้องหลัง
task.spawn(function()
    while true do
        task.wait(12)
        if getgenv().fAstConfig and getgenv().fAstConfig.AutoClaimRewards then
            ClaimAllRewards(true)
        end
    end
end)

-- // 8. AUTO BOSS SMART COMBAT ENGINE (ตีตรงจังหวะ ไม่ตีมั่ว หันหาบอสเฉพาะตอนสู้) // --
local lastAttackTime = 0
local hadBossFighting = false
local isPerformingUltimate = false
local ultCastTime = 0

getgenv()._BossCombatLoop = RunService.Heartbeat:Connect(function()
    if not getgenv().fAstConfig or not getgenv().fAstConfig.AutoBoss then return end

    local char = LocalPlayer.Character
    if not char then return end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local myHum = char:FindFirstChildOfClass("Humanoid")
    if not myRoot or not myHum or myHum.Health <= 0 then return end

    local handler = CharacterController:GetCharacterHandler(char)
    if not handler or not handler.ActionManager then return end
    local am = handler.ActionManager

    local targetBoss = FindBossTarget(getgenv().fAstConfig.SelectedBoss)

    -- [ฟังก์ชันช่วยปลดล็อคมุมกล้องเมื่ออยู่นอกการต่อสู้]
    local function ReleaseCameraLock()
        pcall(function()
            local tlc = GameManager:GetController("TargetLockController")
            if tlc and tlc.ForcedTargetLock then
                tlc:SetForcedTargetLock(nil)
            end
        end)
    end

    -- [ตรวจสอบสถานะการต่อสู้]: บอสต้องยังมีชีวิตอยู่จริง
    if not targetBoss or not IsBossAlive(targetBoss) then
        handler.TargetLock = nil
        handler.OverrideLookDirection = nil
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
        handler._desiredQueuedAction = nil
        isPerformingUltimate = false
        ReleaseCameraLock()

        if hadBossFighting then
            hadBossFighting = false
            ShowHUDToast("🏆 บอสตายแล้ว! หยุดโจมตีอัตโนมัติ", Color3.fromRGB(50, 255, 120))
            if TriggerAutoReturnToLobby then
                TriggerAutoReturnToLobby("BossDeathInCombat")
            end
        end
        return
    end

    local bRoot = targetBoss:FindFirstChild("HumanoidRootPart")
    if not bRoot or not IsBossAlive(targetBoss) then
        handler.TargetLock = nil
        handler.OverrideLookDirection = nil
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
        handler._desiredQueuedAction = nil
        isPerformingUltimate = false
        ReleaseCameraLock()
        return
    end

    local toBoss = (bRoot.Position - myRoot.Position)
    local dist = toBoss.Magnitude

    -- ตรวจสอบระยะต่อสู้ (ถ้าอยู่ในห้องสู้บอส ระยะไม่เกิน 85 studs)
    if dist > 85 then
        handler.TargetLock = nil
        handler.OverrideLookDirection = nil
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
        handler._desiredQueuedAction = nil
        isPerformingUltimate = false
        ReleaseCameraLock()
        return
    end

    hadBossFighting = true

    -- [ตรวจจับสถานะอันติ]: ดูว่าอยู่ในจังหวะร่ายหรือท่าอนิเมชันอันติหรือไม่
    local currentAct = am.CurrentAction
    local actName = currentAct and tostring(currentAct.Name) or ""
    local isUltActionActive = (currentAct and (currentAct.ActionType == "Ultimate" or string.find(actName, "Ultimate"))) or (tick() - ultCastTime < 1.4)
    if not isUltActionActive then
        isPerformingUltimate = false
    end

    -- [A] ล็อคเป้าตัวละคร + หันมุมกล้อง (Camera) เข้าหาบอสอัตโนมัติ
    local flatToBoss = Vector3.new(toBoss.X, 0, toBoss.Z)
    local flatUnit = flatToBoss.Magnitude > 0.1 and flatToBoss.Unit or myRoot.CFrame.LookVector
    local lookTarget = Vector3.new(bRoot.Position.X, bRoot.Position.Y, bRoot.Position.Z)

    handler.TargetLock = bRoot
    handler.OverrideLookDirection = flatUnit
    handler.DesiredLookDirection = flatUnit
    handler.DesiredLookResponsiveness = 999

    if handler.PhysicsComponent and handler.PhysicsComponent.AlignOrientation then
        handler.PhysicsComponent.AlignOrientation.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
    end

    -- หมุนมุมกล้อง (Camera) ให้หันจับเป้าบอสที่กำลังสู้อยู่แบบนุ่มนวล
    pcall(function()
        local tlc = GameManager:GetController("TargetLockController")
        if tlc and tlc.ForcedTargetLock ~= bRoot then
            tlc:SetForcedTargetLock(bRoot)
        end
    end)

    local cam = workspace.CurrentCamera
    if cam then
        local camFocus = bRoot.Position + Vector3.new(0, 1.2, 0)
        local targetCamCF = CFrame.lookAt(cam.CFrame.Position, camFocus)
        cam.CFrame = cam.CFrame:Lerp(targetCamCF, 0.25)
    end

    -- ระยะเป้าหมายระดับประชิด: 2.5 studs เพื่อให้ฟันโดน 100% ทุกอาวุธ (ไม่ฟันลม)
    local targetDist = (isPerformingUltimate or isUltActionActive) and 2.2 or 2.5
    local approachPos = Vector3.new(
        bRoot.Position.X - flatUnit.X * targetDist,
        bRoot.Position.Y,
        bRoot.Position.Z - flatUnit.Z * targetDist
    )

    if isPerformingUltimate or isUltActionActive then
        -- ล็อคตัวละครเกาะติดหน้าบอสแบบ Magnetic Lock ตลอดการร่ายอันติ แม้บอสจะกระโดดหรือถอยหลัง
        myRoot.CFrame = CFrame.lookAt(approachPos, bRoot.Position)
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
    else
        if dist > 3.0 then
            handler.DesiredMoveDirection = flatUnit
            myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(approachPos, bRoot.Position), 0.5)
        else
            handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
            myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(approachPos, bRoot.Position), 0.35)
        end
    end

    -- [B] ระบบโจมตีอัตโนมัติคอมโบต่อเนื่อง & อันติแม่นยำ 100%
    if dist <= 7.5 and IsBossAlive(targetBoss) then
        -- 1. แทงปิดฉากเมื่อบอสการ์ดแตก (Critical Strike)
        local critTarget = CharacterController.CriticalStrikeTarget
        if critTarget then
            ReplicatedStorage.Remotes.PlayerCharacter.Request.CriticalStrike:FireServer(critTarget.Parent)
        elseif isPerformingUltimate or isUltActionActive then
            -- กำลังออกท่าอันติ: งดแทรก Light Attack หรือคลิกเมาส์ เพื่อให้อันติฟันเข้าเป้าครบ 100% ไม่หลุดคอมโบ
        else
            -- 2. ปล่อย Ultimate ทันทีที่เกจเต็ม (100% Energy)
            if handler:CanPerformUltimate() then
                isPerformingUltimate = true
                ultCastTime = tick()

                -- วาร์ปประกบหน้าบอสระดับ 2.8 studs ในเสี้ยววินาทีก่อนปล่อยอันติ
                myRoot.CFrame = CFrame.new(Vector3.new(bRoot.Position.X - flatUnit.X * 2.8, myRoot.Position.Y, bRoot.Position.Z - flatUnit.Z * 2.8), lookTarget)

                handler._desiredQueuedAction = "Ultimate"
                am:TryQueueBasicAttack("Ultimate")
                ShowHUDToast("🔥 ใช้อันติล็อกเป้าบอส (Ultimate)!", Color3.fromRGB(255, 60, 60))
            else
                -- 3. รันคอมโบ Light Attack ตลอดเวลาที่ Action ว่าง
                if not am._queuedActionType then
                    handler._desiredQueuedAction = "LightAttack"
                    am:TryQueueBasicAttack("Light")
                end

                -- คลิกเสมือนเสริมให้ออกดาบต่อเนื่องไม่มีสะดุด
                local now = tick()
                if now - lastAttackTime >= 0.1 then
                    lastAttackTime = now
                    pcall(function()
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                        task.wait(0.015)
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end)
                end
            end
        end
    end
end)

-- // 8. MODERN CYBER-AESTHETIC GLASS UI (fAst Hub) // --
pcall(function()
    if guiParent:FindFirstChild("fAstHub_DG") then
        guiParent.fAstHub_DG:Destroy()
    end
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("fAstHub_DG") then
        LocalPlayer.PlayerGui.fAstHub_DG:Destroy()
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "fAstHub_DG"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 99999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Name = "MainFrame"
Main.Size = UDim2.new(0, 338, 0, 400)
Main.Position = UDim2.new(0.04, 0, 0.15, 0)
Main.BackgroundColor3 = Color3.fromRGB(15, 13, 24)
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local MainGrad = Instance.new("UIGradient")
MainGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 19, 40)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 14, 26)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 9, 18))
})
MainGrad.Rotation = 45
MainGrad.Parent = Main

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.6
MainStroke.Color = Color3.fromRGB(155, 75, 255)
MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainStroke.Parent = Main

-- TopBar (Header)
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 46)
TopBar.BackgroundColor3 = Color3.fromRGB(26, 21, 42)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 14)
TopCorner.Parent = TopBar

local TopGrad = Instance.new("UIGradient")
TopGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 27, 56)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 16, 32))
})
TopGrad.Parent = TopBar

local TopLine = Instance.new("Frame")
TopLine.Name = "AccentLine"
TopLine.Size = UDim2.new(1, 0, 0, 1.5)
TopLine.Position = UDim2.new(0, 0, 1, -1.5)
TopLine.BackgroundColor3 = Color3.fromRGB(140, 60, 240)
TopLine.BorderSizePixel = 0
TopLine.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(0, 95, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.Text = "fAst Hub"
Title.TextColor3 = Color3.fromRGB(245, 240, 255)
Title.TextSize = 16
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local TagBadge = Instance.new("Frame")
TagBadge.Name = "TagBadge"
TagBadge.Size = UDim2.new(0, 42, 0, 18)
TagBadge.Position = UDim2.new(0, 98, 0.5, -9)
TagBadge.BackgroundColor3 = Color3.fromRGB(80, 35, 145)
TagBadge.BorderSizePixel = 0
TagBadge.Parent = TopBar

local TagCorner = Instance.new("UICorner")
TagCorner.CornerRadius = UDim.new(0, 5)
TagCorner.Parent = TagBadge

local TagText = Instance.new("TextLabel")
TagText.Size = UDim2.new(1, 0, 1, 0)
TagText.BackgroundTransparency = 1
TagText.Font = Enum.Font.GothamBold
TagText.Text = "PRO"
TagText.TextColor3 = Color3.fromRGB(225, 190, 255)
TagText.TextSize = 9.5
TagText.Parent = TagBadge

local KeyChip = Instance.new("Frame")
KeyChip.Name = "KeyChip"
KeyChip.Size = UDim2.new(0, 78, 0, 20)
KeyChip.Position = UDim2.new(0, 148, 0.5, -10)
KeyChip.BackgroundColor3 = Color3.fromRGB(20, 17, 30)
KeyChip.BorderSizePixel = 0
KeyChip.Parent = TopBar

local ChipCorner = Instance.new("UICorner")
ChipCorner.CornerRadius = UDim.new(0, 6)
ChipCorner.Parent = KeyChip

local ChipStroke = Instance.new("UIStroke")
ChipStroke.Thickness = 1
ChipStroke.Color = Color3.fromRGB(70, 55, 105)
ChipStroke.Parent = KeyChip

local ChipText = Instance.new("TextLabel")
ChipText.Size = UDim2.new(1, 0, 1, 0)
ChipText.BackgroundTransparency = 1
ChipText.Font = Enum.Font.GothamMedium
ChipText.Text = "[Right Ctrl]"
ChipText.TextColor3 = Color3.fromRGB(170, 140, 240)
ChipText.TextSize = 10.5
ChipText.Parent = KeyChip

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(36, 30, 52)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 110, 110)
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(1, 0)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(180, 35, 45), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(36, 30, 52), TextColor3 = Color3.fromRGB(255, 110, 110)}):Play()
end)

-- Dragging System
local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Content Frame
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -56)
Content.Position = UDim2.new(0, 10, 0, 52)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.Parent = Main

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 6)
UIList.Parent = Content

-- Helper: Create Standard Card Row with Sticker Image
local function CreateRowCard(name, height, iconAssetId, iconTint, titleText, titleColor)
    local card = Instance.new("Frame")
    card.Name = name
    card.Size = UDim2.new(1, 0, 0, height)
    card.BackgroundColor3 = Color3.fromRGB(22, 19, 34)
    card.BorderSizePixel = 0
    card.Parent = Content

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Thickness = 1
    cardStroke.Color = Color3.fromRGB(48, 40, 70)
    cardStroke.Parent = card

    -- Left Sticker Badge
    local iconBadge = Instance.new("Frame")
    iconBadge.Size = UDim2.new(0, 28, 0, 28)
    iconBadge.Position = UDim2.new(0, 8, 0.5, -14)
    iconBadge.BackgroundColor3 = Color3.fromRGB(30, 25, 46)
    iconBadge.BorderSizePixel = 0
    iconBadge.Parent = card

    local ibCorner = Instance.new("UICorner")
    ibCorner.CornerRadius = UDim.new(0, 7)
    ibCorner.Parent = iconBadge

    local ibStroke = Instance.new("UIStroke")
    ibStroke.Thickness = 1
    ibStroke.Color = iconTint or Color3.fromRGB(85, 60, 130)
    ibStroke.Parent = iconBadge

    local iconImg = Instance.new("ImageLabel")
    iconImg.Size = UDim2.new(0, 18, 0, 18)
    iconImg.Position = UDim2.new(0.5, -9, 0.5, -9)
    iconImg.BackgroundTransparency = 1
    iconImg.Image = iconAssetId
    if iconTint then
        iconImg.ImageColor3 = iconTint
    end
    iconImg.ScaleType = Enum.ScaleType.Fit
    iconImg.Parent = iconBadge

    -- Clean Vertically-Centered English Title
    local lbl = Instance.new("TextLabel")
    lbl.Name = "TitleLabel"
    lbl.Size = UDim2.new(0.58, 0, 0, 20)
    lbl.Position = UDim2.new(0, 44, 0.5, -10)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = titleText
    lbl.TextColor3 = titleColor or Color3.fromRGB(255, 255, 255)
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    return card
end

-- Helper: Create Standard Modern Switch
local function CreateSwitch(parent, onColor)
    local switch = Instance.new("TextButton")
    switch.Name = "Switch"
    switch.Size = UDim2.new(0, 46, 0, 24)
    switch.Position = UDim2.new(1, -54, 0.5, -12)
    switch.BackgroundColor3 = Color3.fromRGB(40, 36, 56)
    switch.BorderSizePixel = 0
    switch.Text = ""
    switch.AutoButtonColor = false
    switch.Parent = parent

    local swCorner = Instance.new("UICorner")
    swCorner.CornerRadius = UDim.new(1, 0)
    swCorner.Parent = switch

    local swStroke = Instance.new("UIStroke")
    swStroke.Thickness = 1
    swStroke.Color = Color3.fromRGB(65, 58, 88)
    swStroke.Parent = switch

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = switch

    local knCorner = Instance.new("UICorner")
    knCorner.CornerRadius = UDim.new(1, 0)
    knCorner.Parent = knob

    local function SetState(val)
        local targetPos = val and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        local targetBg = val and onColor or Color3.fromRGB(40, 36, 56)
        local targetStroke = val and onColor or Color3.fromRGB(65, 58, 88)

        TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
        TweenService:Create(switch, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetBg}):Play()
        TweenService:Create(swStroke, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = targetStroke}):Play()
    end

    return switch, SetState
end

-- ==========================================================
-- ROW 1: Auto Parry Keybind
-- ==========================================================
local KeyRow = CreateRowCard("KeyRow", 42, "rbxassetid://121486627050870", Color3.fromRGB(255, 215, 110), "Parry Keybind", Color3.fromRGB(255, 215, 110))
local KeyBtn = Instance.new("TextButton")
KeyBtn.Name = "KeybindBtn"
KeyBtn.Size = UDim2.new(0, 68, 0, 26)
KeyBtn.Position = UDim2.new(1, -76, 0.5, -13)
KeyBtn.BackgroundColor3 = Color3.fromRGB(36, 30, 52)
KeyBtn.BorderSizePixel = 0
KeyBtn.Font = Enum.Font.GothamBold
KeyBtn.Text = "[" .. getgenv().fAstConfig.ParryKeybind.Name .. "]"
KeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KeyBtn.TextSize = 11.5
KeyBtn.Parent = KeyRow

local KeyBtnCorner = Instance.new("UICorner")
KeyBtnCorner.CornerRadius = UDim.new(0, 6)
KeyBtnCorner.Parent = KeyBtn

local KeyBtnStroke = Instance.new("UIStroke")
KeyBtnStroke.Thickness = 1
KeyBtnStroke.Color = Color3.fromRGB(75, 60, 110)
KeyBtnStroke.Parent = KeyBtn

local listening = false
KeyBtn.MouseButton1Click:Connect(function()
    if listening then return end
    listening = true
    KeyBtn.Text = "[...]"
    KeyBtn.TextColor3 = Color3.fromRGB(255, 215, 0)

    local connection
    connection = UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            getgenv().fAstConfig.ParryKeybind = input.KeyCode
            KeyBtn.Text = "[" .. input.KeyCode.Name .. "]"
            KeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            ShowHUDToast("Parry Key: " .. input.KeyCode.Name, Color3.fromRGB(255, 215, 0))
            listening = false
            connection:Disconnect()
        end
    end)
end)

-- ==========================================================
-- ROW 2: Auto Parry
-- ==========================================================
local ParryRow = CreateRowCard("ParryRow", 42, "rbxassetid://10723346959", Color3.fromRGB(185, 120, 255), "Auto Parry", Color3.fromRGB(210, 160, 255))
local ParrySwitch, SetParrySwitchState = CreateSwitch(ParryRow, Color3.fromRGB(150, 70, 255))

local function SetParryState(val)
    getgenv().fAstConfig.AutoParry = val
    SetParrySwitchState(val)
end

ParrySwitch.MouseButton1Click:Connect(function()
    SetParryState(not getgenv().fAstConfig.AutoParry)
    local txt = getgenv().fAstConfig.AutoParry and "AUTO PARRY: ON" or "AUTO PARRY: OFF"
    local col = getgenv().fAstConfig.AutoParry and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- ==========================================================
-- ROW 3: Target Boss Selector (Dropdown)
-- ==========================================================
local BossRow = CreateRowCard("BossRow", 42, "rbxassetid://10734975486", Color3.fromRGB(255, 185, 75), "Target Boss", Color3.fromRGB(255, 185, 75))
BossRow.ClipsDescendants = true

local BossBtn = Instance.new("TextButton")
BossBtn.Name = "BossSelectBtn"
BossBtn.Size = UDim2.new(0, 130, 0, 28)
BossBtn.Position = UDim2.new(1, -138, 0, 7)
BossBtn.BackgroundColor3 = Color3.fromRGB(36, 30, 54)
BossBtn.BorderSizePixel = 0
BossBtn.Font = Enum.Font.GothamBold
BossBtn.Text = BossList[currentBossIndex].Display .. "  v"
BossBtn.TextColor3 = Color3.fromRGB(255, 215, 110)
BossBtn.TextSize = 11.5
BossBtn.Parent = BossRow

local BossBtnCorner = Instance.new("UICorner")
BossBtnCorner.CornerRadius = UDim.new(0, 6)
BossBtnCorner.Parent = BossBtn

local BossBtnStroke = Instance.new("UIStroke")
BossBtnStroke.Thickness = 1
BossBtnStroke.Color = Color3.fromRGB(85, 65, 125)
BossBtnStroke.Parent = BossBtn

local DropdownContainer = Instance.new("Frame")
DropdownContainer.Name = "DropdownContainer"
DropdownContainer.Size = UDim2.new(1, -16, 0, #BossList * 27 + 6)
DropdownContainer.Position = UDim2.new(0, 8, 0, 40)
DropdownContainer.BackgroundColor3 = Color3.fromRGB(15, 13, 22)
DropdownContainer.BorderSizePixel = 0
DropdownContainer.Visible = false
DropdownContainer.ClipsDescendants = true
DropdownContainer.Parent = BossRow

local DropdownCorner = Instance.new("UICorner")
DropdownCorner.CornerRadius = UDim.new(0, 8)
DropdownCorner.Parent = DropdownContainer

local DropdownStroke = Instance.new("UIStroke")
DropdownStroke.Thickness = 1.2
DropdownStroke.Color = Color3.fromRGB(130, 65, 220)
DropdownStroke.Parent = DropdownContainer

local DropdownLayout = Instance.new("UIListLayout")
DropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
DropdownLayout.Padding = UDim.new(0, 2)
DropdownLayout.Parent = DropdownContainer

local DropdownPadding = Instance.new("UIPadding")
DropdownPadding.PaddingTop = UDim.new(0, 3)
DropdownPadding.PaddingBottom = UDim.new(0, 3)
DropdownPadding.PaddingLeft = UDim.new(0, 4)
DropdownPadding.PaddingRight = UDim.new(0, 4)
DropdownPadding.Parent = DropdownContainer

local isDropdownOpen = false
local dropdownItemBtns = {}

local function UpdateDropdownItems()
    for _, btn in ipairs(dropdownItemBtns) do
        local bDisplay = btn:GetAttribute("BossDisplay")
        if bDisplay == getgenv().fAstConfig.SelectedBoss then
            btn.BackgroundColor3 = Color3.fromRGB(75, 35, 130)
            btn.TextColor3 = Color3.fromRGB(255, 230, 120)
            btn.Text = "  > " .. bDisplay
        else
            btn.BackgroundColor3 = Color3.fromRGB(24, 20, 34)
            btn.TextColor3 = Color3.fromRGB(195, 190, 215)
            btn.Text = "     " .. bDisplay
        end
    end
end

local function ToggleDropdown(forceClose)
    if forceClose then
        isDropdownOpen = false
    else
        isDropdownOpen = not isDropdownOpen
    end

    local expandedRowH = 42 + (#BossList * 27 + 8)
    local targetRowH = isDropdownOpen and expandedRowH or 42
    local targetMainH = isDropdownOpen and (400 + (#BossList * 27 + 8)) or 400
    local arrow = isDropdownOpen and "  ^" or "  v"

    BossBtn.Text = getgenv().fAstConfig.SelectedBoss .. arrow

    if isDropdownOpen then
        DropdownContainer.Visible = true
        UpdateDropdownItems()
    end

    TweenService:Create(BossRow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetRowH)}):Play()
    TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 338, 0, targetMainH)}):Play()

    if not isDropdownOpen then
        task.delay(0.2, function()
            if not isDropdownOpen then
                DropdownContainer.Visible = false
            end
        end)
    end
end

for idx, b in ipairs(BossList) do
    local ItemBtn = Instance.new("TextButton")
    ItemBtn.Name = "Item_" .. b.Id
    ItemBtn.Size = UDim2.new(1, 0, 0, 25)
    ItemBtn.BackgroundColor3 = Color3.fromRGB(24, 20, 34)
    ItemBtn.BorderSizePixel = 0
    ItemBtn.Font = Enum.Font.GothamSemibold
    ItemBtn.Text = "     " .. b.Display
    ItemBtn.TextColor3 = Color3.fromRGB(195, 190, 215)
    ItemBtn.TextSize = 11.5
    ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
    ItemBtn:SetAttribute("BossDisplay", b.Display)
    ItemBtn.Parent = DropdownContainer

    local ItemCorner = Instance.new("UICorner")
    ItemCorner.CornerRadius = UDim.new(0, 5)
    ItemCorner.Parent = ItemBtn

    table.insert(dropdownItemBtns, ItemBtn)

    ItemBtn.MouseButton1Click:Connect(function()
        currentBossIndex = idx
        getgenv().fAstConfig.SelectedBoss = b.Display
        getgenv().fAstConfig.SelectedBossId = b.Id
        ShowHUDToast("Selected: " .. b.Display, Color3.fromRGB(255, 185, 75))
        ToggleDropdown(true)
    end)
end

BossBtn.MouseButton1Click:Connect(function()
    ToggleDropdown()
end)

-- ==========================================================
-- ROW 4: Auto Boss
-- ==========================================================
local BossFightRow = CreateRowCard("BossFightRow", 42, "rbxassetid://10734975692", Color3.fromRGB(255, 125, 40), "Auto Boss", Color3.fromRGB(255, 140, 50))
local BossSwitch, SetBossSwitchState = CreateSwitch(BossFightRow, Color3.fromRGB(255, 125, 40))

local function SetBossFightState(val)
    getgenv().fAstConfig.AutoBoss = val
    SetBossSwitchState(val)
end

BossSwitch.MouseButton1Click:Connect(function()
    SetBossFightState(not getgenv().fAstConfig.AutoBoss)
    local txt = getgenv().fAstConfig.AutoBoss and "BOSS BOT: ON" or "BOSS BOT: OFF"
    local col = getgenv().fAstConfig.AutoBoss and Color3.fromRGB(255, 140, 50) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- ==========================================================
-- ROW 5: Auto Return Lobby
-- ==========================================================
local ReturnRow = CreateRowCard("ReturnRow", 42, "rbxassetid://76916186329249", Color3.fromRGB(45, 215, 125), "Auto Return Lobby", Color3.fromRGB(60, 230, 140))
local ReturnSwitch, SetReturnSwitchState = CreateSwitch(ReturnRow, Color3.fromRGB(45, 215, 125))

local function SetReturnLobbyState(val)
    getgenv().fAstConfig.AutoReturnLobby = val
    SetReturnSwitchState(val)
end

ReturnSwitch.MouseButton1Click:Connect(function()
    SetReturnLobbyState(not getgenv().fAstConfig.AutoReturnLobby)
    local txt = getgenv().fAstConfig.AutoReturnLobby and "AUTO RETURN: ON" or "AUTO RETURN: OFF"
    local col = getgenv().fAstConfig.AutoReturnLobby and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- ==========================================================
-- ROW 6: Auto Claim Rewards
-- ==========================================================
local RewardsRow = CreateRowCard("RewardsRow", 42, "rbxassetid://82668203286354", Color3.fromRGB(255, 105, 185), "Auto Claim Rewards", Color3.fromRGB(255, 105, 185))
local RewardsSwitch, SetRewardsSwitchState = CreateSwitch(RewardsRow, Color3.fromRGB(255, 75, 175))

local function SetClaimRewardsState(val)
    getgenv().fAstConfig.AutoClaimRewards = val
    SetRewardsSwitchState(val)
    if val then
        ClaimAllRewards(false)
    end
end

RewardsSwitch.MouseButton1Click:Connect(function()
    SetClaimRewardsState(not getgenv().fAstConfig.AutoClaimRewards)
    local txt = getgenv().fAstConfig.AutoClaimRewards and "AUTO REWARDS: ON" or "AUTO REWARDS: OFF"
    local col = getgenv().fAstConfig.AutoClaimRewards and Color3.fromRGB(255, 105, 185) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- ==========================================================
-- ROW 7: ACTION BUTTONS (Start Fight & Claim Now)
-- ==========================================================
local ActionRow = Instance.new("Frame")
ActionRow.Name = "ActionRow"
ActionRow.Size = UDim2.new(1, 0, 0, 36)
ActionRow.BackgroundTransparency = 1
ActionRow.BorderSizePixel = 0
ActionRow.Parent = Content

-- Button Left: Start Boss Fight
local StartFightBtn = Instance.new("TextButton")
StartFightBtn.Name = "StartFightBtn"
StartFightBtn.Size = UDim2.new(0.63, -3, 1, 0)
StartFightBtn.Position = UDim2.new(0, 0, 0, 0)
StartFightBtn.BackgroundColor3 = Color3.fromRGB(75, 32, 130)
StartFightBtn.BorderSizePixel = 0
StartFightBtn.Font = Enum.Font.GothamBold
StartFightBtn.Text = "Fight Boss"
StartFightBtn.TextColor3 = Color3.fromRGB(235, 205, 255)
StartFightBtn.TextSize = 12
StartFightBtn.Parent = ActionRow

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 9)
StartCorner.Parent = StartFightBtn

local StartStroke = Instance.new("UIStroke")
StartStroke.Thickness = 1.2
StartStroke.Color = Color3.fromRGB(155, 75, 255)
StartStroke.Parent = StartFightBtn

StartFightBtn.MouseButton1Click:Connect(function()
    isReturningLobby = false
    local bId = getgenv().fAstConfig.SelectedBossId
    if bId == "Any" then bId = "Jack" end

    local ep = GameManager:GetController("EventProgressController")
    if ep and ep.RequestStartFight then
        ShowHUDToast("Starting " .. bId .. " Fight...", Color3.fromRGB(255, 180, 50))
        ep:RequestStartFight(bId, "Normal")
    else
        ShowHUDToast("สู้ได้เฉพาะตอนอยู่ในฮับฮาโลวีน", Color3.fromRGB(255, 80, 80))
    end
end)

-- Button Right: Claim All Rewards Now
local ClaimNowBtn = Instance.new("TextButton")
ClaimNowBtn.Name = "ClaimNowBtn"
ClaimNowBtn.Size = UDim2.new(0.37, -3, 1, 0)
ClaimNowBtn.Position = UDim2.new(0.63, 3, 0, 0)
ClaimNowBtn.BackgroundColor3 = Color3.fromRGB(130, 26, 75)
ClaimNowBtn.BorderSizePixel = 0
ClaimNowBtn.Font = Enum.Font.GothamBold
ClaimNowBtn.Text = "Claim Rewards"
ClaimNowBtn.TextColor3 = Color3.fromRGB(255, 210, 235)
ClaimNowBtn.TextSize = 12
ClaimNowBtn.Parent = ActionRow

local ClaimCorner = Instance.new("UICorner")
ClaimCorner.CornerRadius = UDim.new(0, 9)
ClaimCorner.Parent = ClaimNowBtn

local ClaimStroke = Instance.new("UIStroke")
ClaimStroke.Thickness = 1.2
ClaimStroke.Color = Color3.fromRGB(255, 80, 160)
ClaimStroke.Parent = ClaimNowBtn

ClaimNowBtn.MouseButton1Click:Connect(function()
    ClaimAllRewards(false)
end)

-- ตั้งค่าสถานะเริ่มต้นของสวิตช์ตาม fAstConfig (ปิดทั้งหมดเป็นค่าเริ่มต้น)
SetParryState(getgenv().fAstConfig.AutoParry)
SetBossFightState(getgenv().fAstConfig.AutoBoss)
SetReturnLobbyState(getgenv().fAstConfig.AutoReturnLobby)
SetClaimRewardsState(getgenv().fAstConfig.AutoClaimRewards)

-- Floating Quick Toggle Pill (ปุ่มลอยสำหรับคลิกเปิด/ปิด UI ได้ตลอดเวลา แม้อยู่ในคอมแบท)
local FloatingPill = Instance.new("TextButton")
FloatingPill.Name = "FloatingPill"
FloatingPill.Size = UDim2.new(0, 92, 0, 28)
FloatingPill.Position = UDim2.new(0.04, 0, 0.1, 0)
FloatingPill.BackgroundColor3 = Color3.fromRGB(20, 16, 32)
FloatingPill.BorderSizePixel = 0
FloatingPill.Font = Enum.Font.GothamBold
FloatingPill.Text = "⚡ fAst Hub"
FloatingPill.TextColor3 = Color3.fromRGB(225, 185, 255)
FloatingPill.TextSize = 11.5
FloatingPill.Visible = not Main.Visible
FloatingPill.Active = true
FloatingPill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 8)
PillCorner.Parent = FloatingPill

local PillStroke = Instance.new("UIStroke")
PillStroke.Thickness = 1.2
PillStroke.Color = Color3.fromRGB(155, 75, 255)
PillStroke.Parent = FloatingPill

-- Dragging System for FloatingPill
local pDragging, pDragInput, pDragStart, pStartPos
FloatingPill.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        pDragging = true
        pDragStart = input.Position
        pStartPos = FloatingPill.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                pDragging = false
            end
        end)
    end
end)
FloatingPill.InputChanged:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and pDragging then
        local delta = input.Position - pDragStart
        FloatingPill.Position = UDim2.new(pStartPos.X.Scale, pStartPos.X.Offset + delta.X, pStartPos.Y.Scale, pStartPos.Y.Offset + delta.Y)
    end
end)

-- Menu Visibility Controls
local function ToggleVisibility()
    Main.Visible = not Main.Visible
    FloatingPill.Visible = not Main.Visible
    if not Main.Visible then
        ToggleDropdown(true)
    else
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end)
    end
end

FloatingPill.MouseButton1Click:Connect(function()
    ToggleVisibility()
end)

CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    FloatingPill.Visible = true
    ToggleDropdown(true)
    ShowHUDToast("ปิดเมนูแล้ว (กด [Right Ctrl] หรือคลิกปุ่มลอย ⚡ เพื่อเปิด)", Color3.fromRGB(170, 90, 255))
end)

-- Keybind Listeners
getgenv()._fAstInputConn = UserInputService.InputBegan:Connect(function(input, processed)
    -- เปิด/ปิดเมนูได้ 100% ตลอดเวลา แม้อยู่ระหว่างต่อสู้กับบอส (ไม่ต้องสนใจ processed)
    if input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.Insert or input.KeyCode == Enum.KeyCode.RightAlt then
        ToggleVisibility()
        return
    end

    if processed then return end

    if input.KeyCode == getgenv().fAstConfig.ParryKeybind then
        SetParryState(not getgenv().fAstConfig.AutoParry)
        local statusText = getgenv().fAstConfig.AutoParry and "AUTO PARRY: ON" or "AUTO PARRY: OFF"
        local statusColor = getgenv().fAstConfig.AutoParry and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
        ShowHUDToast(statusText, statusColor)
    end
end)

ShowHUDToast("⚡ fAst Hub v10 โหลดสำเร็จ (กด [Right Ctrl] หรือคลิกปุ่มลอยเพื่อเปิด)", Color3.fromRGB(170, 90, 255))
print("[cook45] fAst Hub V10 (Modern Cyber Glass UI + Auto Rewards) Active!")
