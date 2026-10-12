local CombatService = {}
CombatService.__index = CombatService

local validHitPartNames = {
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    UpperTorso = true,
    LowerTorso = true,
    Head = true,
}
local skillCategories = {
    { Name = "Melee", Token = "Melee", Keys = { "Z", "X", "C" } },
    { Name = "Sword", Token = "Sword", Keys = { "Z", "X" } },
    { Name = "Gun", Token = "Gun", Keys = { "Z", "X" } },
    { Name = "Blox Fruit", Token = "BloxFruit", Keys = { "Z", "X", "C", "V", "F" } },
}

function CombatService.new(compatibility, enemyService)
    local dependencies, dependencyError = compatibility:GetCombatDependencies()
    if not dependencies then
        return nil, dependencyError
    end
    return setmetatable({
        Compatibility = compatibility,
        EnemyService = enemyService,
        Dependencies = dependencies,
        AttackIndex = 0,
        FruitAttackIndex = 1,
        NextGunM1At = 0,
    }, CombatService)
end

function CombatService:FindWeapon(category)
    local player = self.Compatibility.Player
    local backpack = player and player:FindFirstChild("Backpack")
    local character = player and player.Character
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == category then
                return item
            end
        end
    end
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == category then
                return item
            end
        end
    end
    return nil
end

function CombatService:FindToolByName(toolName)
    local player = self.Compatibility.Player
    local character = player and player.Character
    local backpack = player and player:FindFirstChild("Backpack")
    local containers = {}
    if character then
        table.insert(containers, character)
    end
    if backpack then
        table.insert(containers, backpack)
    end
    for _, container in ipairs(containers) do
        local tool = container:FindFirstChild(toolName)
        if tool and tool:IsA("Tool") then
            return tool
        end
    end
    return nil
end

function CombatService:EquipTool(tool)
    if not tool or not tool:IsA("Tool") then
        return false, "Selected tool is unavailable"
    end
    local character, humanoid = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or humanoid.Sit then
        return false, "Character cannot equip a tool"
    end
    if tool.Parent ~= character then
        local player = self.Compatibility.Player
        local backpack = player and player:FindFirstChild("Backpack")
        if tool.Parent ~= backpack then
            return false, "Selected tool is not in the character or Backpack"
        end
        humanoid:EquipTool(tool)
    end
    if tool.Parent ~= character then
        return false, "Selected tool did not equip"
    end
    return true, tool
end

function CombatService:EquipWeapon(category)
    local tool = self:FindWeapon(category)
    if not tool then
        return false, "No owned " .. tostring(category) .. " tool was found"
    end
    return self:EquipTool(tool)
end

function CombatService:_FindReadySkill(isEnabled, preferredCategory, ignoredTools, onlyCategory)
    local playerGui = self.Compatibility:GetPlayerGui()
    local main = playerGui and playerGui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    if not skills then
        return nil, "PlayerGui.Main.Skills is unavailable"
    end

    local orderedCategories = {}
    for _, category in ipairs(skillCategories) do
        if category.Name == preferredCategory then
            table.insert(orderedCategories, 1, category)
        else
            table.insert(orderedCategories, category)
        end
    end
    for _, category in ipairs(orderedCategories) do
        if not onlyCategory or category.Name == onlyCategory then
            local tool = self:FindWeapon(category.Name)
            local selectedKeys = {}
            for _, keyName in ipairs(category.Keys) do
                if isEnabled(category, keyName) then
                    table.insert(selectedKeys, keyName)
                end
            end
            if tool and #selectedKeys > 0 and not (ignoredTools and ignoredTools[tool.Name]) then
                local toolSkills = skills:FindFirstChild(tool.Name)
                if not toolSkills then
                    local equipped, equipResult = self:EquipTool(tool)
                    if not equipped then
                        return nil, tostring(equipResult)
                    end
                    return nil, "Waiting for skill UI for " .. tool.Name, tool
                end
                for _, keyName in ipairs(selectedKeys) do
                    local frame = toolSkills:FindFirstChild(keyName)
                    local title = frame and frame:FindFirstChild("Title")
                    local cooldown = frame and frame:FindFirstChild("Cooldown")
                    local titleText = title and title:IsA("TextLabel") and title.Text or ""
                    local isReady = frame
                        and frame:IsA("Frame")
                        and title
                        and title:IsA("TextLabel")
                        and title.TextColor3 == Color3.new(1, 1, 1)
                        and cooldown
                        and cooldown:IsA("GuiObject")
                        and cooldown.Size.X.Scale == 0
                        and cooldown.Size.X.Offset == 0
                        and not string.find(titleText, "Transformation", 1, true)
                    if isReady then
                        return {
                            Tool = tool,
                            Category = category.Name,
                            Key = keyName,
                            Setting = "FarmSkill_" .. category.Token .. "_" .. keyName,
                        }
                    end
                end
            end
        end
    end
    return nil, "No selected skill is currently ready"
end

function CombatService:FindReadyFarmSkill(farmSettings, preferredCategory, ignoredTools, onlyCategory)
    return self:_FindReadySkill(function(category, keyName)
        return farmSettings["FarmSkill_" .. category.Token .. "_" .. keyName] == true
    end, preferredCategory, ignoredTools, onlyCategory)
end

function CombatService:FindReadyTikiSkill()
    return self:_FindReadySkill(function()
        return true
    end)
end

function CombatService:UseSkill(tool, keyName, target, holdSeconds, shouldContinue)
    if not tool or not tool:IsA("Tool") or type(keyName) ~= "string" then
        return false, "Skill input is invalid"
    end
    if not target or not target.Parent or target:GetAttribute("AlreadyDestroyedClient") == true then
        return false, "Skill target is no longer available"
    end

    local targetPart
    if target:IsA("BasePart") then
        targetPart = target
    elseif target:IsA("Model") then
        targetPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
            or target:FindFirstChildWhichIsA("BasePart", true)
    end
    if not targetPart or not targetPart:IsA("BasePart") then
        return false, "Skill target has no aimable BasePart"
    end

    local equipped, equipResult = self:EquipTool(tool)
    if not equipped then
        return false, tostring(equipResult)
    end

    local inputOk, inputService = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not inputOk or not inputService then
        return false, "VirtualInputManager is unavailable in this runtime"
    end

    local mouse = self.Dependencies.Mouse
    if type(mouse) ~= "table" then
        return false, "ReplicatedStorage.Mouse did not expose the BNN aim table"
    end
    local readAimOk, oldHit, oldTarget = pcall(function()
        return mouse.Hit, mouse.Target
    end)
    if not readAimOk then
        return false, "ReplicatedStorage.Mouse aim state is unreadable"
    end

    local setAimOk = pcall(function()
        mouse.Hit = targetPart.CFrame
        mouse.Target = targetPart
    end)
    local verifyAimOk, assignedHit, assignedTarget = pcall(function()
        return mouse.Hit, mouse.Target
    end)
    if not setAimOk or not verifyAimOk
        or typeof(assignedHit) ~= "CFrame"
        or (assignedHit.Position - targetPart.Position).Magnitude > 0.1
        or assignedTarget ~= targetPart
    then
        pcall(function()
            mouse.Hit = oldHit
            mouse.Target = oldTarget
        end)
        return false, "ReplicatedStorage.Mouse rejected the temporary skill aim target"
    end

    local function restoreAim()
        pcall(function()
            mouse.Hit = oldHit
            mouse.Target = oldTarget
        end)
    end
    local pressed, pressError = pcall(function()
        inputService:SendKeyEvent(true, keyName, false, game)
    end)
    if not pressed then
        restoreAim()
        return false, "Skill key press failed: " .. tostring(pressError)
    end
    self.ActiveInputService = inputService
    self.ActiveSkillKey = keyName

    local holdDuration = math.clamp(tonumber(holdSeconds) or 0.5, 0.05, 5)
    local holdUntil = os.clock() + holdDuration
    local waitOk, waitError = pcall(function()
        while os.clock() < holdUntil do
            if shouldContinue and not shouldContinue() then
                break
            end
            task.wait(math.min(0.05, math.max(0.01, holdUntil - os.clock())))
        end
    end)

    local releaseOk, releaseError = pcall(function()
        inputService:SendKeyEvent(false, keyName, false, game)
    end)
    self.ActiveInputService = nil
    self.ActiveSkillKey = nil
    restoreAim()

    if not releaseOk then
        return false, "Skill key release failed: " .. tostring(releaseError)
    end
    if not waitOk then
        return false, "Skill hold failed: " .. tostring(waitError)
    end
    return true, keyName .. " skill key sent"
end

function CombatService:UseTikiSkill(tool, keyName, target, holdSeconds, shouldContinue)
    return self:UseSkill(tool, keyName, target, holdSeconds, shouldContinue)
end

function CombatService:AttackGunM1(target)
    if not self.EnemyService:IsAlive(target) then
        return false, "Gun M1 target is no longer alive"
    end
    if not target:IsA("Model") then
        return false, "Gun M1 target is not an enemy model"
    end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
        or target.PrimaryPart
    if not targetRoot or not targetRoot:IsA("BasePart") then
        return false, "Gun M1 target has no HumanoidRootPart"
    end

    local character, _, playerRoot = self.Compatibility:GetCharacterParts()
    if not character or not playerRoot then
        return false, "Gun M1 character is unavailable"
    end
    if (playerRoot.Position - targetRoot.Position).Magnitude >= 70 then
        return false, "Gun M1 target is outside firing range"
    end

    local now = os.clock()
    if now < (self.NextGunM1At or 0) then
        return false, "Gun M1 is cooling down"
    end

    local tool = self:FindWeapon("Gun")
    if not tool then
        return false, "No owned Gun tool was found"
    end
    local equipped, equipResult = self:EquipTool(tool)
    if not equipped then
        return false, tostring(equipResult)
    end
    if character:FindFirstChild(tool.Name) ~= tool then
        return false, "Gun M1 weapon did not equip"
    end

    local combatUtil = self.Dependencies.CombatUtil
    if not combatUtil or type(combatUtil.IsGunReloading) ~= "function" then
        return false, "CombatUtil reload check is unavailable"
    end
    local reloadOk, isReloading = pcall(combatUtil.IsGunReloading, combatUtil, tool)
    if not reloadOk then
        return false, "Gun reload check failed: " .. tostring(isReloading)
    end
    if isReloading then
        return false, "Gun is reloading"
    end

    local function getGunCooldown()
        local cooldown = 0.25
        local cooldownValue = tool:FindFirstChild("Cooldown")
        if cooldownValue
            and (
                cooldownValue:IsA("NumberValue")
                or cooldownValue:IsA("IntValue")
            )
        then
            cooldown = tonumber(cooldownValue.Value) or cooldown
        elseif type(combatUtil.GetWeaponData) == "function" then
            local dataOk, weaponData = pcall(combatUtil.GetWeaponData, combatUtil, tool.Name)
            if dataOk and type(weaponData) == "table" then
                cooldown = tonumber(weaponData.Cooldown) or cooldown
            end
        end
        return math.clamp(cooldown, 0.05, 5)
    end

    if tool.Name == "Skull Guitar" then
        local skullRemote = tool:FindFirstChild("RemoteEvent")
        if not skullRemote or not skullRemote:IsA("RemoteEvent") then
            return false, "Skull Guitar has no RemoteEvent"
        end
        local tapSent, tapError = pcall(function()
            skullRemote:FireServer("TAP", targetRoot.Position)
        end)
        if not tapSent then
            return false, "Skull Guitar TAP request failed: " .. tostring(tapError)
        end
        self.NextGunM1At = now + getGunCooldown()
        return true, "BNN-style Skull Guitar TAP request issued; server damage is not confirmed"
    end

    local replicatedStorage = self.Compatibility.ReplicatedStorage
    local controllers = replicatedStorage and replicatedStorage:FindFirstChild("Controllers")
    local modules = replicatedStorage and replicatedStorage:FindFirstChild("Modules")
    local remotes = replicatedStorage and replicatedStorage:FindFirstChild("Remotes")
    local combatControllerModule = controllers
        and controllers:FindFirstChild("CombatController")
    local netModule = modules and modules:FindFirstChild("Net")
    local validator2 = remotes and remotes:FindFirstChild("Validator2")
    if not combatControllerModule or not netModule or not validator2 then
        return false, "BNN gun M1 controller or validator dependency is unavailable"
    end
    local shootGunEvent = netModule:FindFirstChild("RE/ShootGunEvent")
    if not shootGunEvent then
        return false, "Modules.Net.RE/ShootGunEvent is unavailable"
    end

    local controllerOk, combatController = pcall(require, combatControllerModule)
    if not controllerOk or type(combatController) ~= "table"
        or type(combatController.Attack) ~= "function"
    then
        return false, "CombatController.Attack could not be loaded"
    end

    local debugLibrary = debug
    if type(debugLibrary) ~= "table"
        or type(debugLibrary.getupvalues) ~= "function"
        or type(debugLibrary.getupvalue) ~= "function"
        or type(debugLibrary.setupvalue) ~= "function"
    then
        return false, "Executor debug upvalue APIs are unavailable"
    end
    local allUpvaluesOk, allUpvalues = pcall(
        debugLibrary.getupvalues,
        combatController.Attack
    )
    local validatorState = allUpvaluesOk
        and type(allUpvalues) == "table"
        and allUpvalues[9]
    if not validatorState then
        return false, "CombatController validator state at upvalue 9 is unavailable"
    end

    local function readUpvalue(index)
        local readOk, firstValue, secondValue = pcall(
            debugLibrary.getupvalue,
            validatorState,
            index
        )
        if not readOk then
            return nil
        end
        if secondValue ~= nil then
            return secondValue
        end
        return firstValue
    end
    local state15 = readUpvalue(15)
    local state13 = readUpvalue(13)
    local modulus = readUpvalue(16)
    local divisor = readUpvalue(17)
    local current = readUpvalue(14)
    local seed = readUpvalue(12)
    local counter = readUpvalue(18)
    if type(state15) ~= "number"
        or type(state13) ~= "number"
        or type(modulus) ~= "number"
        or modulus == 0
        or type(divisor) ~= "number"
        or divisor == 0
        or type(current) ~= "number"
        or type(seed) ~= "number"
        or type(counter) ~= "number"
    then
        return false, "CombatController validator upvalues do not match the BNN layout"
    end

    local y = seed * state13
    local validatorValue = (
        (current * state13 + seed * state15) % modulus * modulus
        + y
    ) % divisor
    local updatedCurrent = math.floor(validatorValue / modulus)
    local updatedSeed = validatorValue - updatedCurrent * modulus
    local updatedCounter = counter + 1

    local setupOk, setupError = pcall(function()
        debugLibrary.setupvalue(validatorState, 15, state15)
        debugLibrary.setupvalue(validatorState, 13, state13)
        debugLibrary.setupvalue(validatorState, 16, modulus)
        debugLibrary.setupvalue(validatorState, 17, divisor)
        debugLibrary.setupvalue(validatorState, 14, updatedCurrent)
        debugLibrary.setupvalue(validatorState, 12, updatedSeed)
        debugLibrary.setupvalue(validatorState, 18, updatedCounter)
    end)
    if not setupOk then
        return false, "CombatController validator state update failed: " .. tostring(setupError)
    end

    local validatorSent, validatorError = pcall(function()
        validator2:FireServer(math.floor(validatorValue / divisor * 16777215), updatedCounter)
    end)
    if not validatorSent then
        return false, "Validator2 gun request failed: " .. tostring(validatorError)
    end

    local gunSent, gunError
    if tool.Name == "Cannon" then
        gunSent, gunError = pcall(function()
            shootGunEvent:FireServer(target)
        end)
    else
        gunSent, gunError = pcall(function()
            shootGunEvent:FireServer(targetRoot.Position, { targetRoot })
        end)
    end
    if not gunSent then
        return false, "ShootGunEvent gun request failed: " .. tostring(gunError)
    end

    self.NextGunM1At = now + getGunCooldown()
    return true, "BNN-style gun M1 request issued; server damage is not confirmed"
end

function CombatService:TapSkullGuitar(targetPosition)
    if typeof(targetPosition) ~= "Vector3" then
        return false, "Skull Guitar target position is invalid"
    end
    local tool = self:FindToolByName("Skull Guitar")
    if not tool then
        return false, "Owned Skull Guitar is not loaded into the character or Backpack"
    end
    local equipped, equipResult = self:EquipTool(tool)
    if not equipped then
        return false, tostring(equipResult)
    end

    local combatUtil = self.Dependencies.CombatUtil
    if not combatUtil or type(combatUtil.IsGunReloading) ~= "function" then
        return false, "CombatUtil reload check is unavailable"
    end
    local reloadOk, isReloading = pcall(combatUtil.IsGunReloading, combatUtil, tool)
    if not reloadOk then
        return false, "Skull Guitar reload check failed: " .. tostring(isReloading)
    end
    if isReloading then
        return false, "Skull Guitar is reloading"
    end

    local remote = tool:FindFirstChild("RemoteEvent")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "Loaded Skull Guitar has no supported RemoteEvent"
    end
    local fireOk, fireError = pcall(function()
        remote:FireServer("TAP", targetPosition)
    end)
    if not fireOk then
        return false, "Skull Guitar puzzle request failed: " .. tostring(fireError)
    end
    return true, "Owned Skull Guitar puzzle request issued"
end

function CombatService:_FindBladeHitParts(character, root, range)
    local enemies = self.Compatibility.Workspace:FindFirstChild("Enemies")
    if not enemies then
        return {}
    end

    local parts = {}
    for _, model in ipairs(enemies:GetChildren()) do
        if model ~= character and model:IsDescendantOf(self.Compatibility.Workspace) then
            local targetRoot = model:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local effectiveRange = range
                local points = { targetRoot.Position }
                if targetRoot.Size.Y > 5 then
                    table.insert(
                        points,
                        (targetRoot.CFrame * CFrame.new(0, -targetRoot.Size.Y * 1.5 + 3, 0)).Position
                    )
                end

                for _, point in ipairs(points) do
                    if (point - root.Position).Magnitude < 10 + effectiveRange + targetRoot.Size.X / 2 then
                        for _, part in ipairs(model:GetChildren()) do
                            if part:IsA("BasePart")
                                and (part.Position - root.Position).Magnitude
                                    <= effectiveRange + targetRoot.Size.X / 2
                            then
                                table.insert(parts, part)
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    return parts
end

function CombatService:_GetAttackCandidates(character, root, range)
    local combatUtil = self.Dependencies.CombatUtil
    local candidates, seenRigs = {}, {}
    for _, hitPart in ipairs(self:_FindBladeHitParts(character, root, range)) do
        local rig = combatUtil:GetRigOfHitPart(hitPart)
        if rig and not seenRigs[rig] and validHitPartNames[hitPart.Name] and combatUtil:IsVulnerable(rig) then
            local summoner = rig:FindFirstChild("Summoner")
            local ownSummoner = character:FindFirstChild("Summoner")
            local ownSummonerCharacter = ownSummoner and ownSummoner.Value
            local allowed = rig ~= character
                and (not ownSummonerCharacter or rig ~= ownSummonerCharacter.Character)
                and (not summoner
                    or summoner.Value ~= game:GetService("Players"):GetPlayerFromCharacter(character))
            if allowed then
                table.insert(candidates, { rig, hitPart })
                seenRigs[rig] = true
            end
        end
    end
    return candidates
end

function CombatService:_AttackFruitM1(target, character, root)
    local targetPart = target and (target.PrimaryPart or target:FindFirstChild("HumanoidRootPart"))
    if not targetPart then
        return false, "Fruit M1 target is unavailable"
    end

    local aimPosition = targetPart.Position
    local direction = aimPosition - root.Position
    if direction.Magnitude <= 0 then
        return false, "Fruit M1 target direction is unavailable"
    end
    direction = direction.Unit

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool or tool.ToolTip ~= "Blox Fruit" then
        return false, "Selected fruit tool is not equipped"
    end

    local leftClickRemote = tool:FindFirstChild("LeftClickRemote")
    local remoteFunction = tool:FindFirstChild("RemoteFunction")
    local remoteEvent = tool:FindFirstChild("RemoteEvent")
    if not leftClickRemote and remoteFunction then
        if remoteEvent then
            remoteEvent:FireServer(aimPosition)
        end
        remoteFunction:InvokeServer("TAP")
        return true, "Fruit M1 request issued"
    end

    if leftClickRemote and tool.Name == "Mammoth-Mammoth" then
        leftClickRemote:FireServer(direction)
        return true, "Fruit M1 request issued"
    end
    if leftClickRemote then
        self.FruitAttackIndex += 1
        if self.FruitAttackIndex > 5 then
            self.FruitAttackIndex = 1
        end
        leftClickRemote:FireServer(direction, self.FruitAttackIndex)
        return true, "Fruit M1 request issued"
    end
    return false, "Selected fruit tool has no supported M1 remote"
end

function CombatService:AttackM1(target, range, weaponCategory, attackNoAnimation)
    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or not root or not self.EnemyService:IsAlive(target) then
        return false, "Target or character is invalid"
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot or (root.Position - targetRoot.Position).Magnitude >= 70 then
        return false, "Target is outside ClickM1 range"
    end

    weaponCategory = weaponCategory or "Melee"
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool or tool.ToolTip ~= weaponCategory then
        return false, "Selected weapon category is not equipped"
    end

    if weaponCategory == "Blox Fruit" then
        local fruitIssued, fruitResult = self:_AttackFruitM1(target, character, root)
        if fruitIssued then
            return true, fruitResult
        end
    end

    local stun = character:FindFirstChild("Stun")
    if not stun or stun.Value ~= 0 then
        return false, "Character is stunned or has no Stun state"
    end

    local combatUtil = self.Dependencies.CombatUtil
    local weaponName = combatUtil:GetWeaponName(tool)
    local weaponData = combatUtil:GetWeaponData(weaponName)
    if not weaponData then
        return false, "CombatUtil weapon data is unavailable"
    end

    local weaponType = weaponData.WeaponType
    if not combatUtil:CanAttack(character, weaponType) then
        return false, "CombatUtil rejected attack timing"
    end

    local candidates = self:_GetAttackCandidates(character, root, tonumber(range) or 30)
    if #candidates == 0 then
        return false, "No valid hit parts in BNN attack range"
    end

    local hitPart = table.remove(candidates, 1)[2]
    if attackNoAnimation == true then
        self.Dependencies.RegisterAttack:FireServer(0)
        self.Dependencies.RegisterHit:FireServer(hitPart, candidates)
        return true, "M1 request issued without animation"
    end

    local animationCache = combatUtil:GetMovesetAnimCache(humanoid)
    if not animationCache or not weaponData.Moveset or not weaponData.Moveset.Basic then
        return false, "CombatUtil moveset data is unavailable"
    end
    local basics = weaponData.Moveset.Basic
    if #basics == 0 then
        return false, "Weapon has no basic attack animations"
    end
    self.AttackIndex = self.AttackIndex % #basics + 1

    local pureWeaponName = combatUtil:GetPureWeaponName(weaponName)
    local animation = animationCache[pureWeaponName .. "-basic" .. self.AttackIndex]
    if not animation then
        return false, "Basic attack animation is not cached"
    end

    local speedMultiplier = animation:GetAttribute("SpeedMult") or 1
    if speedMultiplier <= 0 then
        speedMultiplier = 1
    end
    local duration = animation.Length / speedMultiplier

    self.Dependencies.RegisterAttack:FireServer(duration)
    self.Dependencies.RegisterHit:FireServer(hitPart, candidates)
    animation:Play(0.1, 1, speedMultiplier)

    return true, "M1 request issued"
end

function CombatService:Cancel()
    if self.ActiveInputService and self.ActiveSkillKey then
        pcall(function()
            self.ActiveInputService:SendKeyEvent(false, self.ActiveSkillKey, false, game)
        end)
    end
    self.ActiveInputService = nil
    self.ActiveSkillKey = nil
    return true
end

return CombatService
