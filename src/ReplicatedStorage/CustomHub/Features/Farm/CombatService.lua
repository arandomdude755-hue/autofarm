local CombatService = {}
CombatService.__index = CombatService
local SkillAimRedirect = require(script.Parent.SkillAimRedirect)

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

local function listSkillUiToolNames(skills)
    if not skills then
        return "missing"
    end
    local names = {}
    for _, child in ipairs(skills:GetChildren()) do
        table.insert(names, child.Name)
    end
    if #names == 0 then
        return "none"
    end
    return table.concat(names, ", ")
end

local function listCategoryToolNames(container, categoryName)
    if not container then
        return "missing"
    end
    local names = {}
    for _, item in ipairs(container:GetChildren()) do
        if item:IsA("Tool") and item.ToolTip == categoryName then
            table.insert(names, item.Name)
        end
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

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
        NextGunM1At = {},
        NextFruitM1At = {},
    }, CombatService)
end

function CombatService:FindEquippedWeapon(category)
    local player = self.Compatibility.Player
    local character = player and player.Character
    if not character then
        return nil, "Character is unavailable"
    end
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA("Tool") and item.ToolTip == category then
            return item
        end
    end
    return nil, "No equipped " .. tostring(category) .. " tool is available"
end

function CombatService:ResetGunM1Cooldown(tool)
    if tool and self.NextGunM1At then
        self.NextGunM1At[tool] = nil
        return true
    end
    return false
end

function CombatService:FindWeapon(category)
    local player = self.Compatibility.Player
    local backpack = player and player:FindFirstChild("Backpack")
    local character = player and player.Character
    -- Prefer Skull Guitar for the Gun category wherever it is currently loaded:
    -- AttackGunM1 selects TAP only after this tool is actually equipped.
    if category == "Gun" then
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool")
                    and item.ToolTip == "Gun"
                    and item.Name == "Skull Guitar"
                then
                    return item
                end
            end
        end
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool")
                    and item.ToolTip == "Gun"
                    and item.Name == "Skull Guitar"
                then
                    return item
                end
            end
        end
    end
    -- Otherwise prefer any matching equipped tool before a hotbar tool.
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == category then
                return item
            end
        end
    end
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == category then
                return item
            end
        end
    end
    return nil
end

function CombatService:FindSkillWeapon(category, preferEquipped)
    local player = self.Compatibility.Player
    local backpack = player and player:FindFirstChild("Backpack")
    local character = player and player.Character

    if preferEquipped then
        local equipped = self:FindEquippedWeapon(category)
        if equipped then
            return equipped
        end
    end

    local function findMatchingTool(container, exactName)
        if not container then
            return nil
        end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool")
                and item.ToolTip == category
                and (not exactName or item.Name == exactName)
            then
                return item
            end
        end
        return nil
    end

    -- Preserve the existing non-Mastery Skull Guitar preference, then mirror
    -- BNN's NameWeapon order: hotbar Backpack first, equipped Character next.
    if category == "Gun" and not preferEquipped then
        local skullGuitar = findMatchingTool(backpack, "Skull Guitar")
            or findMatchingTool(character, "Skull Guitar")
        if skullGuitar then
            return skullGuitar
        end
    end
    return findMatchingTool(backpack) or findMatchingTool(character)
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
    local tool, findError = self:FindWeapon(category)
    if not tool then
        return false, findError or ("No owned " .. tostring(category) .. " tool was found")
    end
    return self:EquipTool(tool)
end

function CombatService:_FindReadySkill(
    isEnabled,
    preferredCategory,
    ignoredTools,
    onlyCategory
)
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
    local incompleteSkillControls
    local unavailableSkillTitle
    local masterySkillNotReady
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
            local tool = self:FindSkillWeapon(category.Name, onlyCategory ~= nil)
            local selectedKeys = {}
            local selectedKeySet = {}
            for _, keyName in ipairs(category.Keys) do
                if isEnabled(category, keyName) then
                    table.insert(selectedKeys, keyName)
                    selectedKeySet[keyName] = true
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
                if onlyCategory then
                    -- BNN equips the selected hotbar tool, then inspects its
                    -- Skills row in the same pass. The UI row can be ready
                    -- before Roblox finishes reparenting the Tool, so do not
                    -- gate skill discovery on Parent changing synchronously.
                    pcall(self.EquipTool, self, tool)
                end
                local toolSkills = skills:FindFirstChild(tool.Name)
                if not toolSkills then
                    local equipped, equipResult = self:EquipTool(tool)
                    if not equipped then
                        return nil, tostring(equipResult), tool
                    end
                    return nil,
                        "Waiting for PlayerGui.Main.Skills entry '"
                            .. tool.Name .. "' (entries: "
                            .. listSkillUiToolNames(skills) .. ")",
                        tool
                end
                for _, frame in ipairs(toolSkills:GetChildren()) do
                    local keyName = frame.Name
                    local selectedKey = selectedKeySet[keyName]
                    local title = frame and frame:FindFirstChild("Title")
                    local cooldown = frame and frame:FindFirstChild("Cooldown")
                    local titleText = title and title:IsA("TextLabel") and title.Text or ""
                    local cooldownEmpty = cooldown
                        and cooldown:IsA("GuiObject")
                        and cooldown.Size == UDim2.new(0, 0, 1, -1)
                    local cooldownFull = cooldown
                        and cooldown:IsA("GuiObject")
                        and cooldown.Size == UDim2.new(1, 0, 1, -1)
                    local hasSkillControls = frame
                        and frame:IsA("Frame")
                        and title
                        and title:IsA("TextLabel")
                        and cooldown
                        and cooldown:IsA("GuiObject")
                    if frame.Name ~= "Template"
                        and selectedKey
                        and not hasSkillControls
                    then
                        incompleteSkillControls = incompleteSkillControls or (
                            tool.Name .. " " .. keyName .. " controls are incomplete"
                        )
                        if onlyCategory then
                            masterySkillUiTool = masterySkillUiTool or tool
                        end
                    elseif frame.Name ~= "Template"
                        and selectedKey
                        and (titleText == "" or titleText == "???")
                    then
                        unavailableSkillTitle = unavailableSkillTitle or (
                            tool.Name .. " " .. keyName .. " title is unavailable"
                        )
                        if onlyCategory then
                            masterySkillUiTool = masterySkillUiTool or tool
                        end
                    elseif frame.Name ~= "Template"
                        and selectedKey
                        and string.find(titleText, "Transformation", 1, true)
                    then
                        unavailableSkillTitle = unavailableSkillTitle or (
                            tool.Name .. " " .. keyName .. " is not an attack skill"
                        )
                    elseif frame.Name ~= "Template" and selectedKey then
                        local titleColor = title.TextColor3
                        local titleIsReady = titleColor == Color3.new(1, 1, 1)
                        local isReady = (titleIsReady and cooldownEmpty) or cooldownFull
                        if isReady then
                            return {
                                Tool = tool,
                                Category = category.Name,
                                Key = keyName,
                                Setting = "FarmSkill_" .. category.Token .. "_" .. keyName,
                            }
                        elseif onlyCategory and cooldownEmpty and not cooldownFull
                            and not titleIsReady
                        then
                            masterySkillNotReady = masterySkillNotReady
                                or (tool.Name .. " " .. keyName
                                    .. " is not ready (locked or unavailable)")
                        end
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
        return nil, "No usable " .. missingToolCategory .. " skill weapon is available"
    end
    if incompleteSkillControls then
        return nil,
            "Skill UI incomplete: " .. incompleteSkillControls,
            onlyCategory and masterySkillUiTool or nil
    end
    if unavailableSkillTitle then
        return nil,
            "Selected skill unavailable: " .. unavailableSkillTitle,
            onlyCategory and masterySkillUiTool or nil
    end
    if masterySkillNotReady then
        return nil, "No selected mastery skill is ready: " .. masterySkillNotReady
    end
    return nil, "All selected skill keys are on cooldown"
end

function CombatService:FindReadyFarmSkill(
    farmSettings,
    preferredCategory,
    ignoredTools,
    onlyCategory
)
    return self:_FindReadySkill(function(category, keyName)
        return farmSettings["FarmSkill_" .. category.Token .. "_" .. keyName] == true
    end, preferredCategory, ignoredTools, onlyCategory)
end

function CombatService:BuildFarmSkillDiagnostic(farmSettings, categoryName, preferEquipped)
    local player = self.Compatibility.Player
    local character = player and player.Character
    local backpack = player and player:FindFirstChild("Backpack")
    local playerGui = self.Compatibility:GetPlayerGui()
    local main = playerGui and playerGui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    local tool = self:FindSkillWeapon(categoryName, preferEquipped == true)
    local toolParent = "none"
    if tool then
        if tool.Parent == character then
            toolParent = "Character"
        elseif tool.Parent == backpack then
            toolParent = "Backpack"
        else
            toolParent = tool.Parent and tool.Parent.Name or "unparented"
        end
    end

    local mainEnabled = "n/a"
    if main and main:IsA("ScreenGui") then
        mainEnabled = tostring(main.Enabled)
    end
    local skillsVisible = "n/a"
    if skills and skills:IsA("GuiObject") then
        skillsVisible = tostring(skills.Visible)
    end
    local entry = skills and tool and skills:FindFirstChild(tool.Name)
    local categoryDefinition
    for _, category in ipairs(skillCategories) do
        if category.Name == categoryName then
            categoryDefinition = category
            break
        end
    end

    local lines = {
        "Category: " .. tostring(categoryName),
        "Tool: " .. (tool and tool.Name or "none")
            .. "; parent=" .. toolParent
            .. "; character matches=" .. listCategoryToolNames(character, categoryName)
            .. "; backpack matches=" .. listCategoryToolNames(backpack, categoryName),
        "GUI: PlayerGui=" .. (playerGui and "present" or "missing")
            .. "; Main=" .. (main and main.ClassName or "missing")
            .. "; Main.Enabled=" .. mainEnabled
            .. "; Skills=" .. (skills and skills.ClassName or "missing")
            .. "; Skills.Visible=" .. skillsVisible,
        "Skills entries: " .. listSkillUiToolNames(skills),
        "Selected tool entry: " .. (entry and "present" or "missing"),
    }

    if categoryDefinition then
        local enabledKeys = {}
        for _, keyName in ipairs(categoryDefinition.Keys) do
            local settingName = "FarmSkill_" .. categoryDefinition.Token .. "_" .. keyName
            if farmSettings and farmSettings[settingName] == true then
                table.insert(enabledKeys, keyName)
                local frame = entry and entry:FindFirstChild(keyName)
                local title = frame and frame:FindFirstChild("Title")
                local cooldown = frame and frame:FindFirstChild("Cooldown")
                local titleText = title
                    and title:IsA("TextLabel")
                    and title.Text
                    or "missing"
                if #titleText > 48 then
                    titleText = titleText:sub(1, 48)
                end
                local titleReady = title
                    and title:IsA("TextLabel")
                    and title.TextColor3 == Color3.new(1, 1, 1)
                local cooldownEmpty = cooldown
                    and cooldown:IsA("GuiObject")
                    and cooldown.Size == UDim2.new(0, 0, 1, -1)
                local cooldownFull = cooldown
                    and cooldown:IsA("GuiObject")
                    and cooldown.Size == UDim2.new(1, 0, 1, -1)
                local hasControls = frame
                    and frame:IsA("Frame")
                    and title
                    and title:IsA("TextLabel")
                    and cooldown
                    and cooldown:IsA("GuiObject")
                local ready = frame
                    and frame.Name ~= "Template"
                    and hasControls
                    and ((titleReady and cooldownEmpty) or cooldownFull)
                table.insert(
                    lines,
                    keyName .. ": frame=" .. (frame and frame.ClassName or "missing")
                        .. "; visible=" .. tostring(frame and frame.Visible or "n/a")
                        .. "; controls=" .. tostring(hasControls == true)
                        .. "; title=" .. tostring(titleText)
                        .. "; titleReady=" .. tostring(titleReady == true)
                        .. "; cooldownEmpty=" .. tostring(cooldownEmpty == true)
                        .. "; cooldownFull=" .. tostring(cooldownFull == true)
                        .. "; ready=" .. tostring(ready == true)
                )
            end
        end
        table.insert(
            lines,
            2,
            "Selected keys: " .. (#enabledKeys > 0 and table.concat(enabledKeys, ", ") or "none")
        )
    else
        table.insert(lines, 2, "Selected keys: no matching skill category")
    end

    return table.concat(lines, "\n")
end

function CombatService:FindReadyTikiSkill()
    return self:_FindReadySkill(function()
        return true
    end)
end

function CombatService:_GetAimTarget(target, preferRoot)
    if not target then
        return nil, nil
    end
    if target:IsA("BasePart") then
        return target, target
    end
    if not target:IsA("Model") then
        return nil, nil
    end

    local preferredParts = preferRoot
        and { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }
        or { "UpperTorso", "Torso", "HumanoidRootPart", "Head" }
    for _, partName in ipairs(preferredParts) do
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
    local targetPart, mouseTarget =
        self:_GetAimTarget(target, aimContext.PreferRoot)
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
    if aimContext.RemoteAim then
        local redirectUpdated, redirectError =
            SkillAimRedirect:Update(aimContext.RemoteAim, targetPart)
        if not redirectUpdated then
            return false, tostring(redirectError)
        end
    end
    aimContext.TargetPart = targetPart
    return true
end

function CombatService:_SetTemporaryAim(target, redirectSkillRemote)
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

    local targetPart, mouseTarget = self:_GetAimTarget(target, redirectSkillRemote == true)
    if not targetPart then
        return nil, "Skill target has no aimable BasePart"
    end
    local remoteAim
    if redirectSkillRemote then
        local redirectError
        remoteAim, redirectError = SkillAimRedirect:Begin(targetPart)
        if not remoteAim then
            return nil, tostring(redirectError)
        end
    end

    local aimContext = {
        Mouse = mouse,
        OldHit = oldHit,
        OldTarget = oldTarget,
        RemoteAim = remoteAim,
        PreferRoot = redirectSkillRemote == true,
    }
    local aimOk, aimError = self:_UpdateTemporaryAim(aimContext, target)
    if not aimOk then
        self:_RestoreTemporaryAim(aimContext)
        return nil, aimError
    end
    return aimContext
end

function CombatService:_RestoreTemporaryAim(aimContext)
    if not aimContext then
        return
    end
    SkillAimRedirect:End(aimContext.RemoteAim)
    if not aimContext.Mouse then
        return
    end
    pcall(function()
        aimContext.Mouse.Hit = aimContext.OldHit
        aimContext.Mouse.Target = aimContext.OldTarget
    end)
end

function CombatService:SetFarmSkillAimTarget(target)
    local targetPart = self:_GetAimTarget(target, true)
    if not targetPart then
        self:ClearFarmSkillAimTarget()
        return false, "Skill target has no aimable BasePart"
    end
    return SkillAimRedirect:SetTarget(targetPart, self)
end

function CombatService:ClearFarmSkillAimTarget()
    return SkillAimRedirect:ClearTarget(self)
end

function CombatService:UseSkill(tool, keyName, target, holdSeconds, shouldContinue)
    if not tool or not tool:IsA("Tool") or type(keyName) ~= "string" then
        return false, "Skill input is invalid"
    end
    if not target or not target.Parent or target:GetAttribute("AlreadyDestroyedClient") == true then
        return false, "Skill target is no longer available"
    end

    local character = self.Compatibility.Player and self.Compatibility.Player.Character
    local equipped, equipResult = self:EquipTool(tool)
    if not equipped then
        return false, tostring(equipResult)
    end
    character = self.Compatibility.Player and self.Compatibility.Player.Character
    if not character or tool.Parent ~= character then
        return false, "Selected skill weapon did not equip"
    end

    local aimContext, aimError = self:_SetTemporaryAim(target, true)
    if not aimContext then
        return false, tostring(aimError)
    end

    -- Match the reference hubs: activate skill keys through VirtualInputManager
    -- on desktop and touch clients alike. Firing GUI signal connections does not
    -- produce a real input event on many mobile executors.
    local inputOk, inputService = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not inputOk or not inputService then
        self:_RestoreTemporaryAim(aimContext)
        return false, "Skill input is unavailable in this runtime"
    end
    local pressed, pressError = pcall(function()
        inputService:SendKeyEvent(true, keyName, false, game)
    end)
    if not pressed then
        self:_RestoreTemporaryAim(aimContext)
        return false, "Skill key press failed: " .. tostring(pressError)
    end
    local inputReleased = false
    local function releaseInput()
        if inputReleased then
            return true
        end
        inputReleased = true
        local releaseOk, releaseError = pcall(function()
            inputService:SendKeyEvent(false, keyName, false, game)
        end)
        SkillAimRedirect:End(aimContext.RemoteAim)
        aimContext.RemoteAim = nil
        if not releaseOk then
            error(releaseError)
        end
        return true
    end
    self.ActiveInputRelease = releaseInput
    self.ActiveInputService = inputService
    self.ActiveSkillKey = keyName

    local holdDuration = math.clamp(tonumber(holdSeconds) or 0.5, 0.05, 5)
    local holdUntil = os.clock() + holdDuration
    local aimUpdateError
    local farmStateChanged = false
    local waitOk, waitError = pcall(function()
        while os.clock() < holdUntil do
            if shouldContinue and not shouldContinue() then
                farmStateChanged = true
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

    local releaseOk, releaseResult = pcall(releaseInput)
    local releaseError = releaseResult == false and "Skill release did not fire" or releaseResult
    if self.ActiveInputRelease == releaseInput then
        self.ActiveInputRelease = nil
        self.ActiveInputService = nil
        self.ActiveSkillKey = nil
    end
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
    if farmStateChanged then
        return false, "Skill input cancelled because farm state changed"
    end
    return true, keyName .. " skill key sent"
end

function CombatService:UseTikiSkill(tool, keyName, target, holdSeconds, shouldContinue)
    return self:UseSkill(tool, keyName, target, holdSeconds, shouldContinue)
end

function CombatService:_GetToolCooldown(tool)
    local cooldownValue = tool and tool:FindFirstChild("Cooldown")
    if cooldownValue
        and (
            cooldownValue:IsA("NumberValue")
            or cooldownValue:IsA("IntValue")
        )
    then
        local cooldown = tonumber(cooldownValue.Value)
        if cooldown and cooldown > 0 then
            return math.clamp(cooldown, 0.05, 5)
        end
    end

    local combatUtil = self.Dependencies.CombatUtil
    if tool and combatUtil and type(combatUtil.GetWeaponData) == "function" then
        local dataOk, weaponData = pcall(combatUtil.GetWeaponData, combatUtil, tool.Name)
        if dataOk and type(weaponData) == "table" then
            local cooldown = tonumber(weaponData.Cooldown)
            if cooldown and cooldown > 0 then
                return math.clamp(cooldown, 0.05, 5)
            end
        end
    end
    return nil
end

function CombatService:_InvokeGunShootInput(tool, targetPart)
    if self.GunM1Active then
        return false, false, "Another gun input is still being processed"
    end
    if type(targetPart) ~= "table"
        and (typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart"))
    then
        return false, false, "Gun target is not a usable part"
    end

    local shootGun, targetAssist, resolveError =
        self.Compatibility:GetGunShootFunction()
    if type(shootGun) ~= "function" or type(targetAssist) ~= "table"
        or type(targetAssist.getTargetInfo) ~= "function"
    then
        return false, false, tostring(resolveError or "Gun target lookup is unavailable")
    end

    local inputService = game:GetService("UserInputService")
    local touchOnly = inputService.TouchEnabled and not inputService.MouseEnabled
    local input = {
        UserInputType = touchOnly
            and Enum.UserInputType.Touch
            or Enum.UserInputType.MouseButton1,
        Position = Vector3.zero,
    }

    local beforeShotsLeft = tonumber(tool:GetAttribute("LocalShotsLeft"))
    local beforeTotalShots = tonumber(tool:GetAttribute("LocalTotalShots"))
    local beforeEnabled = tool.Enabled
    local previousTargetInfo = targetAssist.getTargetInfo
    local overrideTargetInfo = function()
        return { Part = targetPart }
    end

    local overrideOk, overrideError = pcall(function()
        targetAssist.getTargetInfo = overrideTargetInfo
    end)
    if not overrideOk then
        return false, false, "Could not direct gun aim to the selected target: "
            .. tostring(overrideError)
    end

    self.GunM1Active = true
    local callOk, callError = pcall(shootGun, tool, input)
    local restoreOk, restoreError = pcall(function()
        targetAssist.getTargetInfo = previousTargetInfo
    end)

    if not restoreOk then
        self.GunM1Active = false
        return false, false, "Gun target lookup could not be restored: "
            .. tostring(restoreError)
    end
    if not callOk then
        self.GunM1Active = false
        return false, false, "Game gun input failed: " .. tostring(callError)
    end

    local waitOk, waitError = pcall(function()
        local runService = self.Compatibility.RunService
        if runService and runService.Heartbeat then
            runService.Heartbeat:Wait()
        else
            task.wait()
        end
    end)
    if not waitOk then
        self.GunM1Active = false
        return true, false, "Gun input was invoked, but shot-state check failed: "
            .. tostring(waitError)
    end

    local afterShotsLeft = tonumber(tool:GetAttribute("LocalShotsLeft"))
    local afterTotalShots = tonumber(tool:GetAttribute("LocalTotalShots"))
    local reloadObserved = false
    local combatUtil = self.Dependencies.CombatUtil
    if combatUtil and type(combatUtil.IsGunReloading) == "function" then
        local reloadOk, isReloading =
            pcall(combatUtil.IsGunReloading, combatUtil, tool)
        reloadObserved = reloadOk and isReloading == true
    end

    local shotStateChanged = (
        beforeShotsLeft ~= nil
            and afterShotsLeft ~= nil
            and afterShotsLeft < beforeShotsLeft
    ) or (
        beforeTotalShots ~= nil
            and afterTotalShots ~= nil
            and afterTotalShots ~= beforeTotalShots
    ) or (
        beforeEnabled == true and tool.Enabled == false
    ) or reloadObserved

    self.GunM1Active = false
    return true, shotStateChanged, shotStateChanged
        and "Gun client firing state changed; server damage is unconfirmed"
        or "Gun input sent, but no client firing-state change was observed"
end

function CombatService:AttackGunM1(target, requiredTool)
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

    local tool, findError
    if requiredTool then
        tool = requiredTool
        local equippedCharacter = self.Compatibility.Player
            and self.Compatibility.Player.Character
        if not tool:IsA("Tool")
            or tool.Parent ~= equippedCharacter
            or tool.ToolTip ~= "Gun"
        then
            return false, "Selected mastery Gun is no longer equipped"
        end
    else
        tool, findError = self:FindEquippedWeapon("Gun")
    end
    if not tool then
        return false, findError or "No equipped Gun tool is available"
    end
    if character:FindFirstChild(tool.Name) ~= tool then
        return false, "Gun M1 weapon did not equip"
    end
    -- A newly selected hotbar Gun can retain Enabled=false across the swap.
    -- Let the native ShootGun handler decide; reload, ammo, and this service's
    -- per-tool cooldown remain the actual firing gates.
    local localShotsLeft = tonumber(tool:GetAttribute("LocalShotsLeft"))
    if localShotsLeft and localShotsLeft < 1 then
        return false, "Gun has no shots left"
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

    local now = os.clock()
    self.NextGunM1At = self.NextGunM1At or {}
    if now < (self.NextGunM1At[tool] or 0) then
        return false, "Gun M1 is cooling down"
    end

    local inputSent, shotStateChanged, inputResult =
        self:_InvokeGunShootInput(tool, targetRoot)
    if not inputSent then
        return false, tostring(inputResult)
    end

    local cooldown = self:_GetToolCooldown(tool) or 0.25
    self.NextGunM1At[tool] = now + (
        shotStateChanged and cooldown or math.min(cooldown, 0.25)
    )
    return true, tostring(inputResult), shotStateChanged
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

    if not tool.Enabled then
        return false, "Skull Guitar is disabled"
    end
    local now = os.clock()
    self.NextGunM1At = self.NextGunM1At or {}
    if now < (self.NextGunM1At[tool] or 0) then
        return false, "Skull Guitar is cooling down"
    end

    local targetPart = {
        CFrame = CFrame.new(targetPosition),
        Position = targetPosition,
    }
    local inputSent, shotStateChanged, inputResult =
        self:_InvokeGunShootInput(tool, targetPart)
    if not inputSent then
        return false, "Skull Guitar input failed: " .. tostring(inputResult)
    end

    local cooldown = self:_GetToolCooldown(tool) or 0.25
    self.NextGunM1At[tool] = now + (
        shotStateChanged and cooldown or math.min(cooldown, 0.25)
    )
    return true, shotStateChanged
        and "Skull Guitar client firing state changed; puzzle progress is unconfirmed"
        or "Skull Guitar input sent; firing and puzzle progress are unconfirmed"
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

function CombatService:_AttackFruitM1(target, character, root, tool)
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

    if not tool or tool.Parent ~= character or tool.ToolTip ~= "Blox Fruit" then
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

function CombatService:AttackM1(target, range, weaponCategory, attackNoAnimation, requiredTool)
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
    if requiredTool and (not requiredTool:IsA("Tool") or tool ~= requiredTool) then
        return false, "Selected mastery weapon is no longer equipped"
    end
    if not tool or tool.ToolTip ~= weaponCategory then
        return false, "Selected weapon category is not equipped"
    end

    if weaponCategory == "Blox Fruit" then
        self.NextFruitM1At = self.NextFruitM1At or {}
        local now = os.clock()
        if requiredTool and now < (self.NextFruitM1At[tool] or 0) then
            return false, "Blox Fruit M1 is cooling down"
        end
        local fruitCallOk, fruitIssued, fruitResult = pcall(
            self._AttackFruitM1,
            self,
            target,
            character,
            root,
            tool
        )
        if not fruitCallOk then
            return false, "Fruit M1 request failed: " .. tostring(fruitIssued)
        end
        if fruitIssued then
            local cooldown = requiredTool and self:_GetToolCooldown(tool)
            if cooldown then
                self.NextFruitM1At[tool] = now + cooldown
            end
            return true, fruitResult
        end
        return false, fruitResult
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
    if self.ActiveInputRelease then
        pcall(self.ActiveInputRelease)
    elseif self.ActiveInputService and self.ActiveSkillKey then
        pcall(function()
            self.ActiveInputService:SendKeyEvent(false, self.ActiveSkillKey, false, game)
        end)
    end
    self.ActiveInputRelease = nil
    self.ActiveInputService = nil
    self.ActiveSkillKey = nil
    self:ClearFarmSkillAimTarget()
    return true
end

return CombatService
