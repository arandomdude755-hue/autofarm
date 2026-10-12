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
