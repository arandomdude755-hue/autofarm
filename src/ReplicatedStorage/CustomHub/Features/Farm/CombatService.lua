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
        AttackGeneration = 0,
        AttackBusy = false,
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

function CombatService:EquipWeapon(category)
    local tool = self:FindWeapon(category)
    if not tool then
        return false, "No owned " .. tostring(category) .. " tool was found"
    end

    local character, humanoid = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or humanoid.Sit then
        return false, "Character cannot equip a tool"
    end
    if tool.Parent ~= character then
        humanoid:EquipTool(tool)
    end
    if tool.Parent ~= character then
        return false, "Selected tool did not equip"
    end
    return true, tool
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

function CombatService:AttackM1(target, range, weaponCategory)
    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or not root or not self.EnemyService:IsAlive(target) then
        return false, "Target or character is invalid"
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot or (root.Position - targetRoot.Position).Magnitude >= 70 then
        return false, "Target is outside ClickM1 range"
    end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool or tool.ToolTip ~= (weaponCategory or "Melee") then
        return false, "Selected weapon category is not equipped"
    end
    local stun = character:FindFirstChild("Stun")
    if not stun or stun.Value ~= 0 then
        return false, "Character is stunned or has no Stun state"
    end
    if self.AttackBusy then
        return false, "M1 animation cooldown"
    end

    local candidates = self:_GetAttackCandidates(character, root, tonumber(range) or 30)
    if #candidates == 0 then
        return false, "No valid hit parts in BNN attack range"
    end

    local combatUtil = self.Dependencies.CombatUtil
    local animationCache = combatUtil:GetMovesetAnimCache(humanoid)
    local weaponName = combatUtil:GetWeaponName(tool)
    local weaponData = combatUtil:GetWeaponData(weaponName)
    if not animationCache or not weaponData or not weaponData.Moveset or not weaponData.Moveset.Basic then
        return false, "CombatUtil weapon or moveset data is unavailable"
    end

    local weaponType = weaponData.WeaponType
    if not combatUtil:CanAttack(character, weaponType) then
        return false, "CombatUtil rejected attack timing"
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
    local hitPart = table.remove(candidates, 1)[2]

    self.Dependencies.RegisterAttack:FireServer(duration)
    self.Dependencies.RegisterHit:FireServer(hitPart, candidates)
    animation:Play(0.1, 1, speedMultiplier)

    self.AttackBusy = true
    self.AttackGeneration += 1
    local generation = self.AttackGeneration
    task.delay(duration, function()
        if self.AttackGeneration == generation then
            self.AttackBusy = false
        end
    end)
    return true, "M1 request issued"
end

function CombatService:Cancel()
    self.AttackGeneration += 1
    self.AttackBusy = false
end

return CombatService
