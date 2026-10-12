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

    local selectedKeyCount = 0
    local checkedToolCount = 0
    local missingToolCategory
    local ignoredToolName
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
            selectedKeyCount += #selectedKeys
            if #selectedKeys > 0 and not tool then
                missingToolCategory = missingToolCategory or category.Name
            elseif tool and #selectedKeys > 0
                and ignoredTools
                and ignoredTools[tool.Name]
            then
                ignoredToolName = ignoredToolName or tool.Name
            elseif tool and #selectedKeys > 0 then
                checkedToolCount += 1
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
    if selectedKeyCount == 0 then
        return nil, "No selected skill keys are enabled"
    end
    if checkedToolCount == 0 and ignoredToolName then
        return nil, "Skill controls are temporarily unavailable for " .. ignoredToolName
    end
    if checkedToolCount == 0 and missingToolCategory then
        return nil, "No owned " .. missingToolCategory .. " skill weapon is available"
    end
    return nil, "All selected skill keys are on cooldown"
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

function CombatService:_GetAimTarget(target)
    if not target then
        return nil, nil
    end
    if target:IsA("BasePart") then
        return target, target
    end
    if not target:IsA("Model") then
        return nil, nil
    end

    for _, partName in ipairs({ "UpperTorso", "Torso", "HumanoidRootPart", "Head" }) do
        local part = target:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return part, target
        end
    end
    if target.PrimaryPart and target.PrimaryPart:IsA("BasePart") then
        return target.PrimaryPart, target
    end
    local part = target:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part, target
    end
    return nil, nil
end

function CombatService:_UpdateTemporaryAim(aimContext, target)
    local targetPart, mouseTarget = self:_GetAimTarget(target)
    if not targetPart then
        return false, "Skill target has no aimable BasePart"
    end
    local setAimOk = pcall(function()
        aimContext.Mouse.Hit = targetPart.CFrame
        aimContext.Mouse.Target = mouseTarget
    end)
    local verifyAimOk, assignedHit, assignedTarget = pcall(function()
        return aimContext.Mouse.Hit, aimContext.Mouse.Target
    end)
    if not setAimOk or not verifyAimOk
        or typeof(assignedHit) ~= "CFrame"
        or (assignedHit.Position - targetPart.Position).Magnitude > 0.1
        or assignedTarget ~= mouseTarget
    then
        return false, "ReplicatedStorage.Mouse rejected the temporary target-model aim"
    end
    aimContext.TargetPart = targetPart
    return true
end

function CombatService:_SetTemporaryAim(target)
    local mouse = self.Dependencies.Mouse
    if type(mouse) ~= "table" then
        return nil, "ReplicatedStorage.Mouse did not expose the BNN aim table"
    end
    local readAimOk, oldHit, oldTarget = pcall(function()
        return mouse.Hit, mouse.Target
    end)
    if not readAimOk then
        return nil, "ReplicatedStorage.Mouse aim state is unreadable"
    end

    local aimContext = {
        Mouse = mouse,
        OldHit = oldHit,
        OldTarget = oldTarget,
    }
    local aimOk, aimError = self:_UpdateTemporaryAim(aimContext, target)
    if not aimOk then
        self:_RestoreTemporaryAim(aimContext)
        return nil, aimError
    end
    return aimContext
end

function CombatService:_RestoreTemporaryAim(aimContext)
    if not aimContext or not aimContext.Mouse then
        return
    end
    pcall(function()
        aimContext.Mouse.Hit = aimContext.OldHit
        aimContext.Mouse.Target = aimContext.OldTarget
    end)
end

function CombatService:UseSkill(tool, keyName, target, holdSeconds, shouldContinue)
    if not tool or not tool:IsA("Tool") or type(keyName) ~= "string" then
        return false, "Skill input is invalid"
    end
    if not target or not target.Parent or target:GetAttribute("AlreadyDestroyedClient") == true then
        return false, "Skill target is no longer available"
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

    local aimContext, aimError = self:_SetTemporaryAim(target)
    if not aimContext then
        return false, tostring(aimError)
    end
    local pressed, pressError = pcall(function()
        inputService:SendKeyEvent(true, keyName, false, game)
    end)
    if not pressed then
        self:_RestoreTemporaryAim(aimContext)
        return false, "Skill key press failed: " .. tostring(pressError)
    end
    self.ActiveInputService = inputService
    self.ActiveSkillKey = keyName

    local holdDuration = math.clamp(tonumber(holdSeconds) or 0.5, 0.05, 5)
    local holdUntil = os.clock() + holdDuration
    local aimUpdateError
    local waitOk, waitError = pcall(function()
        while os.clock() < holdUntil do
            if shouldContinue and not shouldContinue() then
                break
            end
            local aimUpdated, aimResult = self:_UpdateTemporaryAim(aimContext, target)
            if not aimUpdated then
                aimUpdateError = aimResult
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
    self:_RestoreTemporaryAim(aimContext)

    if not releaseOk then
        return false, "Skill key release failed: " .. tostring(releaseError)
    end
    if not waitOk then
        return false, "Skill hold failed: " .. tostring(waitError)
    end
    if aimUpdateError then
        return false, "Skill aim update failed: " .. tostring(aimUpdateError)
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

    local aimContext, aimError = self:_SetTemporaryAim(target)
    if not aimContext then
        return false, tostring(aimError)
    end
    local activationOk, activationError = pcall(function()
        tool:Activate()
    end)
    local aimWaitOk, aimWaitError = pcall(function()
        local runService = self.Compatibility.RunService
        if runService and runService.Heartbeat then
            runService.Heartbeat:Wait()
        else
            task.wait()
        end
    end)
    self:_RestoreTemporaryAim(aimContext)
    if not activationOk then
        return false, "Gun Tool:Activate failed: " .. tostring(activationError)
    end
    if not aimWaitOk then
        return false, "Gun aim release wait failed: " .. tostring(aimWaitError)
    end
    self.NextGunM1At = now + getGunCooldown()
    return true, "Gun Tool:Activate request issued; server damage is not confirmed"
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
