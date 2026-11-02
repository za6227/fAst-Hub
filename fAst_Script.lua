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
    AutoParry = oldCfg.AutoParry ~= nil and oldCfg.AutoParry or false,
    ParryKeybind = oldCfg.ParryKeybind or Enum.KeyCode.V,
    AutoBoss = oldCfg.AutoBoss ~= nil and oldCfg.AutoBoss or true,
    AutoReturnLobby = oldCfg.AutoReturnLobby ~= nil and oldCfg.AutoReturnLobby or true,
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
        local char = LocalPlayer.Character
        local myRoot = char and char:FindFirstChild("HumanoidRootPart")
        if bRoot and myRoot then
            local toB = (bRoot.Position - myRoot.Position)
            local flatToB = Vector3.new(toB.X, 0, toB.Z)
            local flatUnit = flatToB.Magnitude > 0.1 and flatToB.Unit or Vector3.new(0, 0, -1)
            -- ส่งตำแหน่งอ้างอิงระดับความสูงเดียวกับตัวบอสตรงๆ ระยะ 3.0 studs ด้านหน้า
            -- ทำให้กล่อง Hitbox (ปกติออฟเซ็ต -3.0 ถึง -3.5) ตกใส่จุดกึ่งกลาง HumanoidRootPart ของบอส 100%
            local strikePos = Vector3.new(bRoot.Position.X - flatUnit.X * 3.0, bRoot.Position.Y, bRoot.Position.Z - flatUnit.Z * 3.0)
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

    -- [ตรวจสอบสถานะการต่อสู้]: บอสต้องยังมีชีวิตอยู่จริง
    if not targetBoss or not IsBossAlive(targetBoss) then
        handler.TargetLock = nil
        handler.OverrideLookDirection = nil
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
        handler._desiredQueuedAction = nil
        isPerformingUltimate = false

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
        return
    end

    local toBoss = (bRoot.Position - myRoot.Position)
    local dist = toBoss.Magnitude

    -- [หันหาศัตรูเฉพาะตอนต่อสู้]: ต้องอยู่ในห้องต่อสู้จริง (InCombat) และระยะไม่เกิน 45 studs
    -- ถ้าอยู่นอกห้องดวลหรือยังไม่เริ่มสู้ จะปล่อยให้ผู้เล่นหมุนตัวและควบคุมกล้องเองได้ 100% อิสระ
    local inCombat = targetBoss:GetAttribute("InCombat") == true
    if not inCombat or dist > 45 then
        handler.TargetLock = nil
        handler.OverrideLookDirection = nil
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
        handler._desiredQueuedAction = nil
        isPerformingUltimate = false
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

    -- [A] ล็อคเป้าและหันหน้าหาบอสแบบแม่นยำสูง (Focused Body Lock)
    local flatToBoss = Vector3.new(toBoss.X, 0, toBoss.Z)
    local flatUnit = flatToBoss.Magnitude > 0.1 and flatToBoss.Unit or Vector3.new(0, 0, -1)
    local lookTarget = Vector3.new(bRoot.Position.X, myRoot.Position.Y, bRoot.Position.Z)

    handler.TargetLock = bRoot
    handler.OverrideLookDirection = flatUnit
    handler.DesiredLookDirection = flatUnit
    handler.DesiredLookResponsiveness = 999

    if handler.PhysicsComponent and handler.PhysicsComponent.AlignOrientation then
        handler.PhysicsComponent.AlignOrientation.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
    end

    -- ระยะเป้าหมาย: ถ้าเป็นช่วงอันติให้เกาะติดหน้าบอส 2.8 studs แนบสนิท / ถ้าคอมโบปกติ 3.6 studs
    local targetDist = (isPerformingUltimate or isUltActionActive) and 2.8 or 3.6
    local approachPos = bRoot.Position - flatUnit * targetDist

    if isPerformingUltimate or isUltActionActive then
        -- ล็อคตัวละครเกาะติดหน้าบอสแบบ Magnetic Lock ตลอดการร่ายอันติ แม้บอสจะกระโดดหรือถอยหลัง
        myRoot.CFrame = CFrame.new(Vector3.new(approachPos.X, myRoot.Position.Y, approachPos.Z), lookTarget)
        handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
    else
        if dist > 4.2 then
            handler.DesiredMoveDirection = flatUnit
            myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.new(Vector3.new(approachPos.X, myRoot.Position.Y, approachPos.Z), lookTarget), 0.4)
        else
            handler.DesiredMoveDirection = Vector3.new(0, 0, 0)
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
        end
    end

    -- [B] ระบบโจมตีอัตโนมัติคอมโบต่อเนื่อง & อันติแม่นยำ 100%
    if dist <= 6.5 and IsBossAlive(targetBoss) then
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

-- // 8. COMPACT MINIMALIST UI (fAst Hub) // --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "fAstHub_DG"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Name = "MainFrame"
Main.Size = UDim2.new(0, 326, 0, 408)
Main.Position = UDim2.new(0.05, 0, 0.18, 0)
Main.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.fromRGB(140, 60, 255)
MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainStroke.Parent = Main

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 12)
TopCorner.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(0.6, 0, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.Text = "⚡ fAst Hub"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 16
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local SubTitle = Instance.new("TextLabel")
SubTitle.Name = "SubTitle"
SubTitle.Size = UDim2.new(0.35, 0, 1, 0)
SubTitle.Position = UDim2.new(0, 105, 0, 0)
SubTitle.BackgroundTransparency = 1
SubTitle.Font = Enum.Font.Gotham
SubTitle.Text = "• [Right Ctrl]"
SubTitle.TextColor3 = Color3.fromRGB(170, 90, 255)
SubTitle.TextSize = 11
SubTitle.TextXAlignment = Enum.TextXAlignment.Left
SubTitle.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0, 7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- Dragging
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

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -50)
Content.Position = UDim2.new(0, 10, 0, 48)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.Parent = Main

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 8)
UIList.Parent = Content

-- Row 1: Keybind Selector
local KeyRow = Instance.new("Frame")
KeyRow.Name = "KeyRow"
KeyRow.Size = UDim2.new(1, 0, 0, 48)
KeyRow.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
KeyRow.BorderSizePixel = 0
KeyRow.Parent = Content

local KeyCorner = Instance.new("UICorner")
KeyCorner.CornerRadius = UDim.new(0, 8)
KeyCorner.Parent = KeyRow

local KeyLabel = Instance.new("TextLabel")
KeyLabel.Size = UDim2.new(0.65, 0, 0, 18)
KeyLabel.Position = UDim2.new(0, 12, 0, 6)
KeyLabel.BackgroundTransparency = 1
KeyLabel.Font = Enum.Font.GothamSemibold
KeyLabel.Text = "Auto Parry Keybind"
KeyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
KeyLabel.TextSize = 13
KeyLabel.TextXAlignment = Enum.TextXAlignment.Left
KeyLabel.Parent = KeyRow

local KeySub = Instance.new("TextLabel")
KeySub.Size = UDim2.new(0.65, 0, 0, 16)
KeySub.Position = UDim2.new(0, 12, 0, 25)
KeySub.BackgroundTransparency = 1
KeySub.Font = Enum.Font.Gotham
KeySub.Text = "คลิกเพื่อเปลี่ยนปุ่มเปิด/ปิด"
KeySub.TextColor3 = Color3.fromRGB(150, 150, 175)
KeySub.TextSize = 10.5
KeySub.TextXAlignment = Enum.TextXAlignment.Left
KeySub.Parent = KeyRow

local KeyBtn = Instance.new("TextButton")
KeyBtn.Name = "KeybindBtn"
KeyBtn.Size = UDim2.new(0, 72, 0, 28)
KeyBtn.Position = UDim2.new(1, -82, 0.5, -14)
KeyBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 58)
KeyBtn.BorderSizePixel = 0
KeyBtn.Font = Enum.Font.GothamBold
KeyBtn.Text = "[" .. getgenv().fAstConfig.ParryKeybind.Name .. "]"
KeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KeyBtn.TextSize = 12
KeyBtn.Parent = KeyRow

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 6)
BtnCorner.Parent = KeyBtn

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

-- Row 2: Auto Parry Switch (PVP Defense)
local ParryRow = Instance.new("Frame")
ParryRow.Name = "ParryRow"
ParryRow.Size = UDim2.new(1, 0, 0, 50)
ParryRow.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
ParryRow.BorderSizePixel = 0
ParryRow.Parent = Content

local ParryCorner = Instance.new("UICorner")
ParryCorner.CornerRadius = UDim.new(0, 8)
ParryCorner.Parent = ParryRow

local ParryLabel = Instance.new("TextLabel")
ParryLabel.Size = UDim2.new(0.68, 0, 0, 20)
ParryLabel.Position = UDim2.new(0, 12, 0, 5)
ParryLabel.BackgroundTransparency = 1
ParryLabel.Font = Enum.Font.GothamSemibold
ParryLabel.Text = "Auto Parry"
ParryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ParryLabel.TextSize = 13.5
ParryLabel.TextXAlignment = Enum.TextXAlignment.Left
ParryLabel.Parent = ParryRow

local ParrySub = Instance.new("TextLabel")
ParrySub.Size = UDim2.new(0.68, 0, 0, 16)
ParrySub.Position = UDim2.new(0, 12, 0, 26)
ParrySub.BackgroundTransparency = 1
ParrySub.Font = Enum.Font.Gotham
ParrySub.Text = "ป้องกันการโดนโจมตีจากศัตรู"
ParrySub.TextColor3 = Color3.fromRGB(150, 150, 175)
ParrySub.TextSize = 10.5
ParrySub.TextXAlignment = Enum.TextXAlignment.Left
ParrySub.Parent = ParryRow

local Switch = Instance.new("TextButton")
Switch.Name = "Switch"
Switch.Size = UDim2.new(0, 48, 0, 26)
Switch.Position = UDim2.new(1, -58, 0.5, -13)
Switch.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
Switch.BorderSizePixel = 0
Switch.Text = ""
Switch.AutoButtonColor = false
Switch.Parent = ParryRow

local SwitchCorner = Instance.new("UICorner")
SwitchCorner.CornerRadius = UDim.new(1, 0)
SwitchCorner.Parent = Switch

local Knob = Instance.new("Frame")
Knob.Name = "Knob"
Knob.Size = UDim2.new(0, 20, 0, 20)
Knob.Position = UDim2.new(0, 3, 0.5, -10)
Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Knob.BorderSizePixel = 0
Knob.Parent = Switch

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = Knob

local function SetParryState(val)
    getgenv().fAstConfig.AutoParry = val
    local targetPos = val and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
    local targetColor = val and Color3.fromRGB(140, 60, 255) or Color3.fromRGB(45, 45, 58)

    TweenService:Create(Knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
    TweenService:Create(Switch, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
end

Switch.MouseButton1Click:Connect(function()
    SetParryState(not getgenv().fAstConfig.AutoParry)
    local txt = getgenv().fAstConfig.AutoParry and "AUTO PARRY: ON" or "AUTO PARRY: OFF"
    local col = getgenv().fAstConfig.AutoParry and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- Row 3: Target Boss Selector (Dropdown Menu)
local BossRow = Instance.new("Frame")
BossRow.Name = "BossRow"
BossRow.Size = UDim2.new(1, 0, 0, 48)
BossRow.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
BossRow.BorderSizePixel = 0
BossRow.ClipsDescendants = true
BossRow.Parent = Content

local BossCorner = Instance.new("UICorner")
BossCorner.CornerRadius = UDim.new(0, 8)
BossCorner.Parent = BossRow

local BossLabel = Instance.new("TextLabel")
BossLabel.Size = UDim2.new(0.48, 0, 0, 18)
BossLabel.Position = UDim2.new(0, 12, 0, 6)
BossLabel.BackgroundTransparency = 1
BossLabel.Font = Enum.Font.GothamSemibold
BossLabel.Text = "Target Boss"
BossLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
BossLabel.TextSize = 13
BossLabel.TextXAlignment = Enum.TextXAlignment.Left
BossLabel.Parent = BossRow

local BossSub = Instance.new("TextLabel")
BossSub.Size = UDim2.new(0.48, 0, 0, 16)
BossSub.Position = UDim2.new(0, 12, 0, 25)
BossSub.BackgroundTransparency = 1
BossSub.Font = Enum.Font.Gotham
BossSub.Text = "คลิกเพื่อเลือกบอส"
BossSub.TextColor3 = Color3.fromRGB(150, 150, 175)
BossSub.TextSize = 10.5
BossSub.TextXAlignment = Enum.TextXAlignment.Left
BossSub.Parent = BossRow

local BossBtn = Instance.new("TextButton")
BossBtn.Name = "BossSelectBtn"
BossBtn.Size = UDim2.new(0, 135, 0, 28)
BossBtn.Position = UDim2.new(1, -145, 0, 10)
BossBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 58)
BossBtn.BorderSizePixel = 0
BossBtn.Font = Enum.Font.GothamBold
BossBtn.Text = BossList[currentBossIndex].Display .. "  ▼"
BossBtn.TextColor3 = Color3.fromRGB(255, 215, 100)
BossBtn.TextSize = 11.5
BossBtn.Parent = BossRow

local BossBtnCorner = Instance.new("UICorner")
BossBtnCorner.CornerRadius = UDim.new(0, 6)
BossBtnCorner.Parent = BossBtn

-- Dropdown Menu Container (แผงเมนูเลื่อนลงมา)
local DropdownContainer = Instance.new("Frame")
DropdownContainer.Name = "DropdownContainer"
DropdownContainer.Size = UDim2.new(1, -20, 0, #BossList * 27 + 6)
DropdownContainer.Position = UDim2.new(0, 10, 0, 46)
DropdownContainer.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
DropdownContainer.BorderSizePixel = 0
DropdownContainer.Visible = false
DropdownContainer.ClipsDescendants = true
DropdownContainer.Parent = BossRow

local DropdownCorner = Instance.new("UICorner")
DropdownCorner.CornerRadius = UDim.new(0, 6)
DropdownCorner.Parent = DropdownContainer

local DropdownStroke = Instance.new("UIStroke")
DropdownStroke.Thickness = 1
DropdownStroke.Color = Color3.fromRGB(120, 70, 200)
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
            btn.BackgroundColor3 = Color3.fromRGB(75, 40, 130)
            btn.TextColor3 = Color3.fromRGB(255, 230, 120)
        else
            btn.BackgroundColor3 = Color3.fromRGB(25, 25, 36)
            btn.TextColor3 = Color3.fromRGB(200, 200, 220)
        end
    end
end

local function ToggleDropdown(forceClose)
    if forceClose then
        isDropdownOpen = false
    else
        isDropdownOpen = not isDropdownOpen
    end

    local expandedRowH = 48 + (#BossList * 27 + 12)
    local targetRowH = isDropdownOpen and expandedRowH or 48
    local targetMainH = isDropdownOpen and (408 + (#BossList * 27 + 12)) or 408
    local arrow = isDropdownOpen and "  ▲" or "  ▼"

    BossBtn.Text = getgenv().fAstConfig.SelectedBoss .. arrow

    if isDropdownOpen then
        DropdownContainer.Visible = true
        UpdateDropdownItems()
    end

    TweenService:Create(BossRow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetRowH)}):Play()
    TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 326, 0, targetMainH)}):Play()

    if not isDropdownOpen then
        task.delay(0.2, function()
            if not isDropdownOpen then
                DropdownContainer.Visible = false
            end
        end)
    end
end

-- สร้างปุ่มตัวเลือกบอสแต่ละตัวใน Dropdown
for idx, b in ipairs(BossList) do
    local ItemBtn = Instance.new("TextButton")
    ItemBtn.Name = "Item_" .. b.Id
    ItemBtn.Size = UDim2.new(1, 0, 0, 25)
    ItemBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 36)
    ItemBtn.BorderSizePixel = 0
    ItemBtn.Font = Enum.Font.GothamSemibold
    ItemBtn.Text = "  " .. b.Display
    ItemBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
    ItemBtn.TextSize = 11.5
    ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
    ItemBtn:SetAttribute("BossDisplay", b.Display)
    ItemBtn.Parent = DropdownContainer

    local ItemCorner = Instance.new("UICorner")
    ItemCorner.CornerRadius = UDim.new(0, 4)
    ItemCorner.Parent = ItemBtn

    table.insert(dropdownItemBtns, ItemBtn)

    ItemBtn.MouseButton1Click:Connect(function()
        currentBossIndex = idx
        getgenv().fAstConfig.SelectedBoss = b.Display
        getgenv().fAstConfig.SelectedBossId = b.Id
        ShowHUDToast("Selected: " .. b.Display, Color3.fromRGB(255, 170, 60))
        ToggleDropdown(true)
    end)
end

BossBtn.MouseButton1Click:Connect(function()
    ToggleDropdown()
end)

-- Row 4: Auto Boss Switch
local BossFightRow = Instance.new("Frame")
BossFightRow.Name = "BossFightRow"
BossFightRow.Size = UDim2.new(1, 0, 0, 50)
BossFightRow.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
BossFightRow.BorderSizePixel = 0
BossFightRow.Parent = Content

local BossFightCorner = Instance.new("UICorner")
BossFightCorner.CornerRadius = UDim.new(0, 8)
BossFightCorner.Parent = BossFightRow

local BossFightLabel = Instance.new("TextLabel")
BossFightLabel.Size = UDim2.new(0.68, 0, 0, 20)
BossFightLabel.Position = UDim2.new(0, 12, 0, 5)
BossFightLabel.BackgroundTransparency = 1
BossFightLabel.Font = Enum.Font.GothamSemibold
BossFightLabel.Text = "Auto Boss"
BossFightLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
BossFightLabel.TextSize = 13.5
BossFightLabel.TextXAlignment = Enum.TextXAlignment.Left
BossFightLabel.Parent = BossFightRow

local BossFightSub = Instance.new("TextLabel")
BossFightSub.Size = UDim2.new(0.68, 0, 0, 16)
BossFightSub.Position = UDim2.new(0, 12, 0, 26)
BossFightSub.BackgroundTransparency = 1
BossFightSub.Font = Enum.Font.Gotham
BossFightSub.Text = "สู้บอสอัตโนมัติ + ตีโดน 100% ทุกดอก"
BossFightSub.TextColor3 = Color3.fromRGB(150, 150, 175)
BossFightSub.TextSize = 10.5
BossFightSub.TextXAlignment = Enum.TextXAlignment.Left
BossFightSub.Parent = BossFightRow

local BossSwitch = Instance.new("TextButton")
BossSwitch.Name = "BossSwitch"
BossSwitch.Size = UDim2.new(0, 48, 0, 26)
BossSwitch.Position = UDim2.new(1, -58, 0.5, -13)
BossSwitch.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
BossSwitch.BorderSizePixel = 0
BossSwitch.Text = ""
BossSwitch.AutoButtonColor = false
BossSwitch.Parent = BossFightRow

local BossSwitchCorner = Instance.new("UICorner")
BossSwitchCorner.CornerRadius = UDim.new(1, 0)
BossSwitchCorner.Parent = BossSwitch

local BossKnob = Instance.new("Frame")
BossKnob.Name = "BossKnob"
BossKnob.Size = UDim2.new(0, 20, 0, 20)
BossKnob.Position = UDim2.new(0, 3, 0.5, -10)
BossKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
BossKnob.BorderSizePixel = 0
BossKnob.Parent = BossSwitch

local BossKnobCorner = Instance.new("UICorner")
BossKnobCorner.CornerRadius = UDim.new(1, 0)
BossKnobCorner.Parent = BossKnob

local function SetBossFightState(val)
    getgenv().fAstConfig.AutoBoss = val
    local targetPos = val and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
    local targetColor = val and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(45, 45, 58)

    TweenService:Create(BossKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
    TweenService:Create(BossSwitch, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
end

BossSwitch.MouseButton1Click:Connect(function()
    SetBossFightState(not getgenv().fAstConfig.AutoBoss)
    local txt = getgenv().fAstConfig.AutoBoss and "BOSS BOT: ON" or "BOSS BOT: OFF"
    local col = getgenv().fAstConfig.AutoBoss and Color3.fromRGB(255, 150, 50) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- Row 5: Auto Return Lobby Switch
local ReturnRow = Instance.new("Frame")
ReturnRow.Name = "ReturnRow"
ReturnRow.Size = UDim2.new(1, 0, 0, 50)
ReturnRow.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
ReturnRow.BorderSizePixel = 0
ReturnRow.Parent = Content

local ReturnCorner = Instance.new("UICorner")
ReturnCorner.CornerRadius = UDim.new(0, 8)
ReturnCorner.Parent = ReturnRow

local ReturnLabel = Instance.new("TextLabel")
ReturnLabel.Size = UDim2.new(0.68, 0, 0, 20)
ReturnLabel.Position = UDim2.new(0, 12, 0, 5)
ReturnLabel.BackgroundTransparency = 1
ReturnLabel.Font = Enum.Font.GothamSemibold
ReturnLabel.Text = "Auto Return Lobby"
ReturnLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ReturnLabel.TextSize = 13.5
ReturnLabel.TextXAlignment = Enum.TextXAlignment.Left
ReturnLabel.Parent = ReturnRow

local ReturnSub = Instance.new("TextLabel")
ReturnSub.Size = UDim2.new(0.68, 0, 0, 16)
ReturnSub.Position = UDim2.new(0, 12, 0, 26)
ReturnSub.BackgroundTransparency = 1
ReturnSub.Font = Enum.Font.Gotham
ReturnSub.Text = "เมื่อบอสตาย กลับล็อบบี้ทันที"
ReturnSub.TextColor3 = Color3.fromRGB(150, 150, 175)
ReturnSub.TextSize = 10.5
ReturnSub.TextXAlignment = Enum.TextXAlignment.Left
ReturnSub.Parent = ReturnRow

local ReturnSwitch = Instance.new("TextButton")
ReturnSwitch.Name = "ReturnSwitch"
ReturnSwitch.Size = UDim2.new(0, 48, 0, 26)
ReturnSwitch.Position = UDim2.new(1, -58, 0.5, -13)
ReturnSwitch.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
ReturnSwitch.BorderSizePixel = 0
ReturnSwitch.Text = ""
ReturnSwitch.AutoButtonColor = false
ReturnSwitch.Parent = ReturnRow

local ReturnSwitchCorner = Instance.new("UICorner")
ReturnSwitchCorner.CornerRadius = UDim.new(1, 0)
ReturnSwitchCorner.Parent = ReturnSwitch

local ReturnKnob = Instance.new("Frame")
ReturnKnob.Name = "ReturnKnob"
ReturnKnob.Size = UDim2.new(0, 20, 0, 20)
ReturnKnob.Position = UDim2.new(0, 3, 0.5, -10)
ReturnKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ReturnKnob.BorderSizePixel = 0
ReturnKnob.Parent = ReturnSwitch

local ReturnKnobCorner = Instance.new("UICorner")
ReturnKnobCorner.CornerRadius = UDim.new(1, 0)
ReturnKnobCorner.Parent = ReturnKnob

local function SetReturnLobbyState(val)
    getgenv().fAstConfig.AutoReturnLobby = val
    local targetPos = val and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
    local targetColor = val and Color3.fromRGB(50, 220, 130) or Color3.fromRGB(45, 45, 58)

    TweenService:Create(ReturnKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
    TweenService:Create(ReturnSwitch, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
end

ReturnSwitch.MouseButton1Click:Connect(function()
    SetReturnLobbyState(not getgenv().fAstConfig.AutoReturnLobby)
    local txt = getgenv().fAstConfig.AutoReturnLobby and "AUTO RETURN: ON" or "AUTO RETURN: OFF"
    local col = getgenv().fAstConfig.AutoReturnLobby and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
    ShowHUDToast(txt, col)
end)

-- Row 6: Fast Start Fight Button (เริ่มสู้บอสทันที)
local StartFightBtn = Instance.new("TextButton")
StartFightBtn.Name = "StartFightBtn"
StartFightBtn.Size = UDim2.new(1, 0, 0, 34)
StartFightBtn.BackgroundColor3 = Color3.fromRGB(45, 25, 75)
StartFightBtn.BorderSizePixel = 0
StartFightBtn.Font = Enum.Font.GothamBold
StartFightBtn.Text = "⚔️ เริ่มสู้บอสทันที (Start Boss Fight)"
StartFightBtn.TextColor3 = Color3.fromRGB(220, 180, 255)
StartFightBtn.TextSize = 12
StartFightBtn.Parent = Content

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 8)
StartCorner.Parent = StartFightBtn

local StartStroke = Instance.new("UIStroke")
StartStroke.Thickness = 1
StartStroke.Color = Color3.fromRGB(140, 60, 255)
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

-- ตั้งค่าสถานะเริ่มต้นของสวิตช์ตาม fAstConfig
SetParryState(getgenv().fAstConfig.AutoParry)
SetBossFightState(getgenv().fAstConfig.AutoBoss)
SetReturnLobbyState(getgenv().fAstConfig.AutoReturnLobby)

-- Menu Visibility Controls (กด [X] ปิดหมดเกลี้ยง ไม่มีปุ่มลอยกวนสายตา / กด [Right Ctrl] เพื่อเปิด/ปิด)
local function ToggleVisibility()
    Main.Visible = not Main.Visible
    if not Main.Visible then
        ToggleDropdown(true)
    end
end

CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    ToggleDropdown(true)
    ShowHUDToast("ปิดเมนูแล้ว (กด [Right Ctrl] เพื่อเปิดใหม่)", Color3.fromRGB(170, 90, 255))
end)

-- Keybind Listeners
getgenv()._fAstInputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.RightControl then
        ToggleVisibility()
    end

    if input.KeyCode == getgenv().fAstConfig.ParryKeybind then
        SetParryState(not getgenv().fAstConfig.AutoParry)
        local statusText = getgenv().fAstConfig.AutoParry and "AUTO PARRY: ON" or "AUTO PARRY: OFF"
        local statusColor = getgenv().fAstConfig.AutoParry and Color3.fromRGB(50, 255, 120) or Color3.fromRGB(255, 70, 70)
        ShowHUDToast(statusText, statusColor)
    end
end)

ShowHUDToast("fAst Hub V10: Combo Engine Active!", Color3.fromRGB(255, 140, 40))
print("[cook45] fAst Hub V10 (Relentless Combo Boss Engine) Active!")
