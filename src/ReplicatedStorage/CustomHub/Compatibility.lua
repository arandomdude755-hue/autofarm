local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Compatibility = {}
Compatibility.__index = Compatibility

function Compatibility.new()
    return setmetatable({
        Player = Players.LocalPlayer,
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        RunService = RunService,
        CollectionService = CollectionService,
    }, Compatibility)
end

function Compatibility:GetPlayerGui()
    if not self.Player then
        return nil, "LocalPlayer is unavailable"
    end
    local playerGui = self.Player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil, "PlayerGui is unavailable"
    end
    return playerGui
end

function Compatibility:GetUnparentedInstances()
    local getterOk, getter = pcall(function()
        return getnilinstances
    end)
    if not getterOk or type(getter) ~= "function" then
        return nil
    end

    local callOk, instances = pcall(getter)
    if not callOk or type(instances) ~= "table" then
        return nil
    end
    return instances
end

function Compatibility:GetGunShootFunction()
    if type(self.GunShootFunction) == "function" then
        return self.GunShootFunction
    end

    local controllers = self.ReplicatedStorage:FindFirstChild("Controllers")
    local controllerModule = controllers and controllers:FindFirstChild("CombatController")
    if not controllerModule then
        return nil, "CombatController is unavailable"
    end

    local requireOk, combatController = pcall(require, controllerModule)
    local attack = requireOk and type(combatController) == "table"
        and combatController.Attack
    if type(attack) ~= "function" then
        return nil, "CombatController.Attack is unavailable"
    end

    local shootGun
    local getterOk, getUpvalues = pcall(function()
        return getupvalues
    end)
    if getterOk and type(getUpvalues) == "function" then
        local upvaluesOk, upvalues = pcall(getUpvalues, attack)
        if upvaluesOk and type(upvalues) == "table" then
            shootGun = upvalues[9]
        end
    end

    if type(shootGun) ~= "function" then
        local debugOk, debugLibrary = pcall(function()
            return debug
        end)
        local getUpvalue = debugOk and debugLibrary and debugLibrary.getupvalue
        if type(getUpvalue) == "function" then
            local upvalueOk, _, value = pcall(getUpvalue, attack, 9)
            if upvalueOk then
                shootGun = value
            end
        end
    end

    if type(shootGun) ~= "function" then
        return nil, "CombatController shootGun input is unavailable"
    end

    local infoOk, debugInfo = pcall(function()
        return debug.info
    end)
    if not infoOk or type(debugInfo) ~= "function" then
        return nil, "CombatController shootGun cannot be validated"
    end
    local nameOk, functionName = pcall(debugInfo, shootGun, "n")
    if not nameOk or functionName ~= "shootGun" then
        return nil, "CombatController attack input did not match shootGun"
    end
    self.GunShootFunction = shootGun
    return shootGun
end

function Compatibility:IsTouchEnabled()
    return UserInputService.TouchEnabled
end

function Compatibility:GetViewportSize()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(390, 844)
end

function Compatibility:GetCharacterParts()
    local character = self.Player and self.Player.Character
    if not character then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return character, humanoid, nil
    end
    return character, humanoid, root
end

function Compatibility:GetQuestModules()
    local questsModule = self.ReplicatedStorage:WaitForChild("Quests", 10)
    local guideModule = self.ReplicatedStorage:WaitForChild("GuideModule", 10)
    if not questsModule or not guideModule then
        return nil, nil, "BNN quest modules are unavailable"
    end

    local ok, quests = pcall(require, questsModule)
    if not ok or type(quests) ~= "table" then
        return nil, nil, "ReplicatedStorage.Quests did not return a quest table"
    end

    local guideOk, guide = pcall(require, guideModule)
    if not guideOk or type(guide) ~= "table" then
        return nil, nil, "GuideModule did not return a data table"
    end
    return quests, guide
end

function Compatibility:GetCommF()
    local remotes = self.ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        return nil, "ReplicatedStorage.Remotes.CommF_ is unavailable"
    end
    return commF
end

function Compatibility:HasOwnedInventoryItem(itemName)
    local now = os.clock()
    self.OwnedInventoryCache = self.OwnedInventoryCache or {}
    if now - (self.OwnedInventoryCacheAt or 0) < 1
        and self.OwnedInventoryCache[itemName] ~= nil
    then
        return self.OwnedInventoryCache[itemName]
    end

    local itemServiceModule = self.ReplicatedStorage:FindFirstChild("ItemReplicationService")
    local itemConfigModule = self.ReplicatedStorage:FindFirstChild("ItemConfig")
    if not itemServiceModule or not itemConfigModule then
        return false, "Inventory lookup modules are unavailable"
    end

    local serviceOk, itemService = pcall(require, itemServiceModule)
    local configOk, itemConfig = pcall(require, itemConfigModule)
    if not serviceOk or type(itemService) ~= "table"
        or not configOk or type(itemConfig) ~= "table"
    then
        return false, "Inventory lookup modules could not be loaded"
    end

    local keys = itemService.KEYS
    local quantityKey = type(keys) == "table" and keys.QUANTITY
    if quantityKey == nil or type(itemService.GetItems) ~= "function"
        or type(itemConfig.match) ~= "function"
    then
        return false, "Inventory lookup APIs are unavailable"
    end

    local scanOk, found = pcall(function()
        for item in itemService:GetItems(quantityKey) do
            if item and item.Value and item.Value > 0 then
                local matchOk, itemDefinition = pcall(function()
                    return itemConfig.match(item.ItemId):unwrap()
                end)
                if matchOk and itemDefinition and itemDefinition.Display then
                    local display = itemDefinition.Display
                    local storageKey = itemDefinition.Index
                        and itemDefinition.Index.StorageKey
                    local resolvedName = display.Category == "Blox Fruit"
                            and (storageKey or display.Name)
                        or (display.Name or storageKey)
                    if resolvedName == itemName then
                        return true
                    end
                end
            end
        end
        return false
    end)
    if not scanOk then
        return false, "Inventory scan failed: " .. tostring(found)
    end

    self.OwnedInventoryCache[itemName] = found == true
    self.OwnedInventoryCacheAt = now
    return found == true
end

function Compatibility:GetCombatDependencies()
    local modules = self.ReplicatedStorage:FindFirstChild("Modules")
    local netModule = modules and modules:FindFirstChild("Net")
    local mouseModule = self.ReplicatedStorage:FindFirstChild("Mouse")
    local combatUtilModule = modules and modules:FindFirstChild("CombatUtil")
    if not netModule or not mouseModule or not combatUtilModule then
        return nil, "BNN melee dependency modules are unavailable"
    end

    local registerAttack = netModule:WaitForChild("RE/RegisterAttack", 10)
    if not registerAttack then
        return nil, "Modules.Net.RE/RegisterAttack is unavailable"
    end

    local mouseOk, mouse = pcall(require, mouseModule)
    local combatOk, combatUtil = pcall(require, combatUtilModule)
    local netOk, net = pcall(require, netModule)
    if not mouseOk or not combatOk or not netOk then
        return nil, "BNN melee dependency modules failed to load"
    end

    local hitOk, registerHit = pcall(function()
        return net:RemoteEvent("RegisterHit", true)
    end)
    if not hitOk or not registerHit then
        return nil, "Modules.Net RegisterHit dependency is unavailable"
    end

    return {
        Mouse = mouse,
        CombatUtil = combatUtil,
        Net = net,
        RegisterAttack = registerAttack,
        RegisterHit = registerHit,
    }
end

function Compatibility:IsThirdSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea3"
        or game.PlaceId == 100117331123089
        or game.PlaceId == 7449423635
end

function Compatibility:IsFirstSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea1"
        or game.PlaceId == 2753915549
        or game.PlaceId == 85211729168715
end

function Compatibility:IsSecondSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea2"
        or game.PlaceId == 4442272183
        or game.PlaceId == 79091703265657
end

return Compatibility
