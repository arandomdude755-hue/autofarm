local weaponCategories = { "Melee", "Sword", "Blox Fruit" }
local farmModes = {
    "Level Farm",
    "Aura Farm",
    "Farm Bones",
    "Farm Cake Prince",
    "Farm Tyrant of the Skies",
}
-- Material drop targets ported from the Vxeze reference catalog.
-- Sea indexes are 1=First, 2=Second, 3=Third; materials never travel seas.
local farmMaterialTargets = {
    ["Angel Wings"] = {
        [1] = { "God's Guard", "Shanda", "Royal Squad", "Royal Soldier", "Wysper", "Thunder God" },
    },
    Leather = {
        [1] = { "Pirate", "Brute" },
        [2] = { "Marine Captain" },
        [3] = { "Jungle Pirate", "Forest Pirate", "Musketeer Pirate" },
    },
    ["Scrap Metal"] = {
        [1] = { "Pirate", "Brute" },
        [2] = { "Marine Captain" },
        [3] = { "Jungle Pirate", "Forest Pirate" },
    },
    ["Magma Ore"] = {
        [1] = { "Military Soldier", "Military Spy", "Magma Admiral" },
        [2] = { "Magma Ninja", "Lava Pirate" },
    },
    ["Fish Tail"] = {
        [1] = { "Fishman Warrior", "Fishman Commando", "Fishman Lord" },
        [3] = { "Fishman Raider", "Fishman Captain" },
    },
    Ectoplasm = {
        [2] = { "Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer", "Cursed Captain" },
    },
    ["Mystic Droplet"] = {
        [2] = { "Water Fighter", "Sea Soldier" },
    },
    ["Radioactive Material"] = {
        [2] = { "Factory Staff" },
    },
    ["Vampire Fang"] = {
        [2] = { "Vampire" },
    },
    ["Conjured Cocoa"] = {
        [3] = { "Chocolate Bar Battler", "Cocoa Warrior" },
    },
    ["Dragon Scale"] = {
        [3] = { "Dragon Crew Archer", "Dragon Crew Warrior" },
    },
    Gunpowder = {
        [3] = { "Pistol Billionaire" },
    },
    ["Mini Tusk"] = {
        [3] = { "Mythological Pirate" },
    },
    Bones = {
        [3] = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" },
    },
    ["Demonic Wisp"] = {
        [3] = { "Demonic Soul", "Reborn Skeleton", "Living Zombie", "Posessed Mummy" },
    },
    ["Nightmare Catcher"] = {
        [3] = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" },
    },
}
local farmMaterials = {}
for materialName in pairs(farmMaterialTargets) do
    table.insert(farmMaterials, materialName)
end
table.sort(farmMaterials)
local function getCurrentSeaIndex(compatibility)
    local seaChecks = {
        { Index = 1, Method = "IsFirstSea" },
        { Index = 2, Method = "IsSecondSea" },
        { Index = 3, Method = "IsThirdSea" },
    }
    local currentSeaIndex
    local recognizedSeaCount = 0
    for _, sea in ipairs(seaChecks) do
        local check = compatibility and compatibility[sea.Method]
        if type(check) == "function" then
            local ok, isCurrentSea = pcall(check, compatibility)
            if ok and isCurrentSea == true then
                currentSeaIndex = sea.Index
                recognizedSeaCount += 1
            end
        end
    end
    if recognizedSeaCount ~= 1 then
        return nil
    end
    return currentSeaIndex
end

local function farmMaterialsForCurrentSea(compatibility)
    local currentSea = getCurrentSeaIndex(compatibility)
    if not currentSea then
        return {}
    end
    local available = {}
    for _, materialName in ipairs(farmMaterials) do
        local seaTargets = farmMaterialTargets[materialName][currentSea]
        if type(seaTargets) == "table" and #seaTargets > 0 then
            table.insert(available, materialName)
        end
    end
    return available
end
local travelIslandDestinations = {
    [1] = {
        { Name = "Start Island", Position = Vector3.new(1071, 16, 1427) },
        { Name = "Marine Start", Position = Vector3.new(-2573, 7, 2047) },
        { Name = "Middle Town", Position = Vector3.new(-656, 8, 1437) },
        { Name = "Jungle", Position = Vector3.new(-1250, 12, 341) },
        { Name = "Pirate Village", Position = Vector3.new(-1122, 5, 3856) },
        { Name = "Desert", Position = Vector3.new(1094, 6, 4193) },
        { Name = "Frozen Village", Position = Vector3.new(1198, 27, -1212) },
        { Name = "Marine Fortress", Position = Vector3.new(-4505, 21, 4261) },
        { Name = "Colosseum", Position = Vector3.new(-1428, 7, -3014) },
        { Name = "Skylands 1st Floor", Position = Vector3.new(-4970, 718, -2622) },
        { Name = "Skylands 2nd Floor", Position = Vector3.new(-4813, 904, -1913) },
        { Name = "Upper Skylands", Position = Vector3.new(-7952, 5546, -321) },
        { Name = "Prison", Position = Vector3.new(4854, 6, 740) },
        { Name = "Magma Village", Position = Vector3.new(-5232, 9, 8468) },
        { Name = "Underwater City", Position = Vector3.new(61164, 12, 1819) },
        { Name = "Fountain City", Position = Vector3.new(5133, 5, 4038) },
        { Name = "Cyborg House", Position = Vector3.new(6263, 72, 3998) },
        { Name = "Shanks Room", Position = Vector3.new(-1442, 30, -28) },
        { Name = "Mob Leader Island", Position = Vector3.new(-2850, 8, 5355) },
    },
    [2] = {
        { Name = "Starting Point", Position = Vector3.new(83, 18, 2835) },
        { Name = "Kingdom of Rose", LocationName = "Kingdom of Rose" },
        { Name = "Dark Arena", LocationName = "Dark Arena" },
        { Name = "Flamingo Mansion", Position = Vector3.new(-390, 332, 673) },
        { Name = "Flamingo Room", Position = Vector3.new(2302, 16, 664) },
        { Name = "Green Bit", Position = Vector3.new(-2372, 73, -3167) },
        { Name = "Cafe", Position = Vector3.new(-385, 73, 297) },
        { Name = "Factory", Position = Vector3.new(430, 211, -433) },
        { Name = "Colosseum", Position = Vector3.new(-1837, 45, 1360) },
        { Name = "Ghost Island", Position = Vector3.new(-5572, 195, -795) },
        { Name = "Ghost Island Lower", Position = Vector3.new(-5932, 6, -1189) },
        { Name = "Snow Mountain", Position = Vector3.new(1384, 454, -4990) },
        { Name = "Hot and Cold", Position = Vector3.new(-6027, 15, -5072) },
        { Name = "Magma Side", Position = Vector3.new(-5479, 16, -5247) },
        { Name = "Cursed Ship", Position = Vector3.new(902, 125, 33072) },
        { Name = "Frosted Island", Position = Vector3.new(5400, 29, -6237) },
        { Name = "Forgotten Island", Position = Vector3.new(-3043, 239, -10192) },
        { Name = "Usoapp Island", Position = Vector3.new(4749, 9, 2850) },
        { Name = "Raid Area", Position = Vector3.new(-5555, 330, -5930) },
        { Name = "Mini Sky", Position = Vector3.new(-260, 49326, -35259) },
    },
    [3] = {
        { Name = "Port Town", Position = Vector3.new(-287, 30, 5388) },
        { Name = "Hydra Island", Position = Vector3.new(3399, 73, 1573) },
        { Name = "Secret Temple", Position = Vector3.new(5247, 8, 1097) },
        {
            Name = "Hydra Town",
            Position = Vector3.new(5290, 1005.4, 393.6),
            ExactPosition = true,
        },
        { Name = "Great Tree", Position = Vector3.new(2443, 37, -6573) },
        { Name = "Castle on the Sea", Position = Vector3.new(-5500, 315, -2855) },
        { Name = "Mansion", Position = Vector3.new(-12548, 338, -7481) },
        { Name = "Floating Turtle", Position = Vector3.new(-10016, 333, -8326) },
        { Name = "Haunted Castle", Position = Vector3.new(-9509, 143, 5535) },
        { Name = "Peanut Island", Position = Vector3.new(-2131, 39, -10106) },
        { Name = "Ice Cream Island", Position = Vector3.new(-950, 60, -10907) },
        { Name = "Cake Loaf", Position = Vector3.new(-1762, 39, -11878) },
        { Name = "Tiki Outpost", Position = Vector3.new(-16204, 10, 479) },
        {
            Name = "Dragon Dojo",
            Position = Vector3.new(5700, 1210, 860),
            ExactPosition = true,
        },
    },
}
local function travelIslandsForCurrentSea(compatibility)
    local currentSea = getCurrentSeaIndex(compatibility)
    local destinations = currentSea and travelIslandDestinations[currentSea] or {}
    local options = {}
    for _, destination in ipairs(destinations) do
        table.insert(options, destination.Name)
    end
    return options
end
local function travelNpcSources(compatibility)
    local workspace = compatibility and compatibility.Workspace
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    return {
        {
            Folder = workspace and workspace:FindFirstChild("NPCs"),
            IsLive = true,
        },
        {
            Folder = replicatedStorage and replicatedStorage:FindFirstChild("NPCs"),
            IsLive = false,
        },
    }
end

local function travelNpcRoot(npc)
    local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    return root and root:IsA("BasePart") and root or nil
end

local TRAVEL_NPC_OPTIONS_CACHE_TTL = 5
local travelNpcOptionsCache = {
    Compatibility = nil,
    Sea = nil,
    At = 0,
    Options = {},
}

local function isTravelNpcPositionInCurrentSea(compatibility, position)
    local seaIndex = getCurrentSeaIndex(compatibility)
    if not seaIndex or typeof(position) ~= "Vector3" then
        return false
    end

    local workspace = compatibility and compatibility.Workspace
    local locations = workspace
        and workspace:FindFirstChild("_WorldOrigin")
        and workspace._WorldOrigin:FindFirstChild("Locations")
    for _, destination in ipairs(travelIslandDestinations[seaIndex] or {}) do
        local anchor = destination.Position
        if not anchor and destination.LocationName and locations then
            local location = locations:FindFirstChild(destination.LocationName)
            if location and location:IsA("BasePart") then
                anchor = location.Position
            elseif location and location:IsA("Model") then
                anchor = location:GetPivot().Position
            end
        end
        if anchor
            and Vector2.new(position.X, position.Z).Magnitude > 100
            and (Vector2.new(position.X - anchor.X, position.Z - anchor.Z)).Magnitude <= 5000
        then
            return true
        end
    end
    return false
end

local function travelNpcsForCurrentSea(compatibility)
    local seaIndex = getCurrentSeaIndex(compatibility)
    if not seaIndex then
        return {}
    end
    local now = os.clock()
    if travelNpcOptionsCache.Compatibility == compatibility
        and travelNpcOptionsCache.Sea == seaIndex
        and now - travelNpcOptionsCache.At < TRAVEL_NPC_OPTIONS_CACHE_TTL
    then
        return table.clone(travelNpcOptionsCache.Options)
    end

    local names = {}
    local function considerNpc(npc, isLive, requireCurrentSea)
        if not npc:IsA("Model")
            or string.find(npc.Name, "Boat", 1, true)
            or string.find(npc.Name, "Set Home", 1, true)
        then
            return
        end
        local root = travelNpcRoot(npc)
        if not root then
            return
        end
        local humanoid = isLive and npc:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return
        end
        if (isLive and not requireCurrentSea)
            or isTravelNpcPositionInCurrentSea(compatibility, root.Position)
        then
            names[npc.Name] = true
        end
    end

    for _, source in ipairs(travelNpcSources(compatibility)) do
        for _, npc in ipairs(source.Folder and source.Folder:GetChildren() or {}) do
            considerNpc(npc, source.IsLive, false)
        end
    end

    local registryNames = compatibility
        and type(compatibility.GetNpcCatalogNames) == "function"
        and compatibility:GetNpcCatalogNames()
    for _, name in ipairs(type(registryNames) == "table" and registryNames or {}) do
        if not string.find(name, "Boat", 1, true)
            and not string.find(name, "Set Home", 1, true)
            and type(compatibility.GetNpcModelsByName) == "function"
        then
            local models = compatibility:GetNpcModelsByName(name)
            for _, npc in ipairs(type(models) == "table" and models or {}) do
                considerNpc(
                    npc,
                    npc:IsDescendantOf(compatibility.Workspace),
                    true
                )
                if names[name] then
                    break
                end
            end
        end
    end

    local options = {}
    for name in pairs(names) do
        table.insert(options, name)
    end
    table.sort(options)
    travelNpcOptionsCache = {
        Compatibility = compatibility,
        Sea = seaIndex,
        At = now,
        Options = options,
    }
    return options
end
local farmModeProfiles = {
    ["Farm Bones"] = {
        Sea = "Third Sea",
        MinimumLevel = 2050,
        QuestPrefix = "HauntedQuest",
        QuestName = "HauntedQuest2",
        QuestId = 2,
    },
    ["Farm Cake Prince"] = {
        Sea = "Third Sea",
        MinimumLevel = 2275,
        QuestPrefix = "CakeQuest",
        QuestName = "CakeQuest2",
        QuestId = 2,
        BossName = "Cake Prince",
        IgnoreBossSetting = "IgnoreCakePrince",
    },
    ["Farm Tyrant of the Skies"] = {
        Sea = "Third Sea",
        MinimumLevel = 2575,
        QuestPrefix = "TikiQuest",
        QuestName = "TikiQuest3",
        QuestId = 2,
        BossName = "Tyrant of the Skies",
        TikiEventPhase = true,
    },
}
local farmSkillCategories = {
    { Name = "Melee", Token = "Melee", Keys = { "Z", "X", "C" } },
    { Name = "Sword", Token = "Sword", Keys = { "Z", "X" } },
    { Name = "Gun", Token = "Gun", Keys = { "Z", "X" } },
    { Name = "Blox Fruit", Token = "BloxFruit", Keys = { "Z", "X", "C", "V", "F" } },
}
local farmSkillDefaults = {}
local farmSkillControls = {
    {
        Kind = "sectionHeader",
        Label = "Combat skills",
    },
    {
        Kind = "settingToggle",
        Label = "Use skills while farming",
        Action = "farm.skills.enabled",
        Setting = "UseFarmSkills",
    },
    {
        Kind = "settingSlider",
        Label = "Skill hold duration",
        Action = "farm.skills.holdSeconds.set",
        Setting = "FarmSkillHoldSeconds",
        Min = 0.05,
        Max = 5,
        Step = 0.05,
        Unit = "sec",
    },
    {
        Kind = "settingToggle",
        Label = "Fast skill release",
        Action = "farm.skills.fastRelease",
        Setting = "FarmSkillFastRelease",
    },
    {
        Kind = "collapsibleHeader",
        Label = "Available skill keys",
        GroupId = "farmSkillKeys",
    },
}
for _, category in ipairs(farmSkillCategories) do
    for _, keyName in ipairs(category.Keys) do
        local settingName = "FarmSkill_" .. category.Token .. "_" .. keyName
        farmSkillDefaults[settingName] = true
        table.insert(farmSkillControls, {
            Kind = "settingToggle",
            Label = category.Name .. " " .. keyName,
            Action = "farm.skills." .. category.Token .. "." .. keyName,
            Setting = settingName,
            Groups = { "farmSkillKeys" },
        })
    end
end

local Config = {
    Name = "Custom Hub",
    Version = "UI shell",
    TravelSettings = {
        Island = nil,
        Npc = nil,
    },
    TravelDestinations = travelIslandDestinations,
    IsTravelNpcPositionInCurrentSea = isTravelNpcPositionInCurrentSea,
    TravelNpcsForCurrentSea = travelNpcsForCurrentSea,
    Defaults = {
        SelectedTab = "Main",
        Compact = true,
        UiSize = "Large",
        StatusMaxCharacters = 88,
    },
    FarmSettings = {
        -- Mirrors BNN's `Settings["Select Weapon"] or "Melee"` default.
        WeaponCategories = weaponCategories,
        WeaponCategory = "Melee",
        FarmModes = farmModes,
        FarmModeProfiles = farmModeProfiles,
        FarmMode = "Level Farm",
        FarmMaterials = farmMaterials,
        FarmMaterialTargets = farmMaterialTargets,
        FarmMaterial = "Leather",
        FarmMaterialsEnabled = false,
        FarmMasteryMethods = { "Blox Fruit", "Gun" },
        FarmMastery = false,
        MasteryCategory = "Blox Fruit",
        MasteryHealthPercent = 40,
        MasteryHealthPercentMin = 0,
        MasteryHealthPercentMax = 100,
        MasteryHealthPercentStep = 1,
        AutoModeQuest = false,
        DoubleQuestEnabled = false,
        InstantAcceptQuest = false,
        IgnoreCakePrince = false,
        AuraDistance = 300,
        AuraDistanceMin = 0,
        AuraDistanceMax = 1000,
        AuraDistanceStep = 1,
        BringMobs = false,
        BringMobCount = 2,
        BringMobCountMin = 2,
        BringMobCountMax = 6,
        BringMobCountStep = 1,
        AutoBuso = true,
        UseFarmSkills = false,
        FarmSkillHoldSeconds = 0.5,
        FarmSkillFastRelease = false,
        -- An unset BNN setting follows its animated, CanAttack-validated branch.
        AttackNoAnimation = false,
    },
    StackFarmSettings = {
        AutoAttackCakePrince = false,
        AutoEliteHunter = false,
        HopForEliteHunter = false,
        AttackRipIndra = false,
        AttackSoulReaper = false,
        AttackDoughKing = false,
        AttackDarkbeard = false,
        PrioritizeRipIndra = false,
        PrioritizeDoughKing = false,
        TeleportToFruit = false,
        AutoCollectBerries = false,
        HopForBerries = false,
    },
    StartupSettings = {
        Team = "Marines",
        AutoExecute = false,
    },
    Layout = {
        MobileWidth = 0.86,
        MobileHeight = 0.78,
        DesktopWidth = 0.72,
        DesktopHeight = 0.78,
        ExpandedWidth = 0.98,
        ExpandedHeight = 0.88,
        UiSizeFootprints = {
            Small = 0.88,
            Medium = 0.94,
            Large = 1,
        },
        MinSize = Vector2.new(280, 320),
        MinUsableWidth = 328,
        MaxSize = Vector2.new(920, 740),
        HeaderTop = 7,
        HeaderHeight = 34,
        CloseWidth = 26,
        CloseHeight = 22,
        TitleRightInset = 84,
        SidebarWidthRatio = 0.25,
        SidebarMinWidth = 88,
        SidebarMaxWidth = 224,
        MainPaneMinWidth = 180,
        SidebarSearchHeight = 30,
        SidebarSearchInset = 8,
        SidebarNavTop = 52,
        SidebarNavInsetTop = 4,
        SidebarNavInsetLeft = 5,
        SidebarRowHeight = 27,
        SidebarRowGap = 2,
        SidebarChildRowHeight = 25,
        SidebarChildIndent = 12,
        PageHeaderHeight = 34,
        SectionHeaderHeight = 42,
        StatusTop = 0,
        StatusHeight = 30,
        StatusInset = 8,
        StatusTextTop = 0,
        ScrollContentInset = 18,
        ScrollBottomPadding = 28,
        ScrollBarThickness = 3,
        RowHeight = 42,
        RowInset = 10,
        RowTitleTop = 0,
        RowTitleHeight = 40,
        SelectorTitleTop = 0,
        SelectorTitleHeight = 40,
        SelectorTitleWidth = 120,
        SelectorTitleGap = 8,
        SelectorOptionsTop = 6,
        SelectorOptionsHeight = 28,
        DropdownWidthRatio = 0.5,
        DropdownTitleGap = 8,
        DropdownHeight = 29,
        DropdownValueInset = 10,
        DropdownArrowWidth = 28,
        DropdownArrowInset = 3,
        DropdownOptionHeight = 44,
        SliderTitleHeight = 22,
        SliderTrackTop = 27,
        SliderTrackHeight = 6,
        SliderValueWidth = 72,
        ToggleValueTop = 9,
        ToggleValueWidth = 68,
        ToggleValueHeight = 22,
        ToggleGap = 7,
        Spacing = 8,
        Padding = 9,
        BorderThickness = 1,
    },
    Theme = {
        Background = Color3.fromRGB(12, 14, 19),
        Header = Color3.fromRGB(21, 25, 34),
        TabBar = Color3.fromRGB(13, 16, 22),
        Panel = Color3.fromRGB(18, 21, 29),
        Sidebar = Color3.fromRGB(15, 18, 24),
        Control = Color3.fromRGB(22, 26, 36),
        Selected = Color3.fromRGB(23, 29, 41),
        AccentSoft = Color3.fromRGB(20, 38, 64),
        Border = Color3.fromRGB(37, 42, 54),
        AccentBorder = Color3.fromRGB(59, 130, 246),
        Text = Color3.fromRGB(237, 239, 243),
        MutedText = Color3.fromRGB(157, 165, 177),
        Accent = Color3.fromRGB(59, 130, 246),
        Success = Color3.fromRGB(106, 190, 145),
        Warning = Color3.fromRGB(222, 184, 105),
        Error = Color3.fromRGB(224, 116, 108),
        Font = Enum.Font.Gotham,
        StrongFont = Enum.Font.GothamSemibold,
        MonoFont = Enum.Font.Code,
        TextSizes = {
            Title = 12,
            Control = 12,
            Body = 12,
            Tab = 11,
            Status = 9,
        },
    },
    Tabs = {
        "Main",
        "Farm",
        "Player",
        "Teleport",
        "Status",
        "Settings",
    },
    TabSubsections = {
        Farm = {
            { Label = "Main Farming", Page = "Farm" },
            { Label = "Stack Farming", Page = "StackFarming" },
        },
        Status = {
            { Label = "Event Status", Page = "EventStatus" },
            { Label = "Server Status", Page = "StatusServer" },
        },
        Settings = {
            { Label = "Main settings", Page = "Settings" },
            { Label = "Farm settings", Page = "FarmSettings" },
        },
    },
    CollapsibleDefaults = {
        farmSkillKeys = true,
    },
    Pages = {
        Main = {
            Controls = {
                {
                    Kind = "button",
                    Label = "Run UI self-check",
                    Action = "main.selfCheck",
                },
            },
        },
        Farm = {
            Title = "Main Farming",
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Farm controls",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Farm method",
                    Action = "farm.mode.select",
                    Setting = "FarmMode",
                    Options = farmModes,
                    AllowNoSelection = true,
                    PlaceholderLabel = "Choose a method",
                    LockedBySetting = "FarmMaterialsEnabled",
                    LockedValue = "Farm Materials",
                    LockedStatus = "Farm method locked to Farm Materials.",
                    LockedPlayerMessage = "Turn off Farm Materials to choose a different farm method.",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto quest Cake/Bones/Tyrant",
                    Action = "farm.autoModeQuest",
                    Setting = "AutoModeQuest",
                },
                {
                    Kind = "settingToggle",
                    Label = "Double Quest",
                    Action = "farm.doubleQuest",
                    Setting = "DoubleQuestEnabled",
                },
                {
                    Kind = "settingToggle",
                    Label = "Ignore Cake Prince boss",
                    Action = "farm.ignoreCakePrince",
                    Setting = "IgnoreCakePrince",
                },
                {
                    Kind = "settingSlider",
                    Label = "Aura distance",
                    Action = "farm.auraDistance.set",
                    Setting = "AuraDistance",
                    Min = 0,
                    Max = 1000,
                    Step = 1,
                    Unit = "studs",
                },
                {
                    Kind = "featureToggle",
                    Label = "Start Farm",
                    Action = "farm.main",
                },
                {
                    Kind = "button",
                    Label = "Copy status report",
                    Action = "farm.status.copy",
                },
                {
                    Kind = "sectionHeader",
                    Label = "Farm Mastery",
                },
                {
                    Kind = "settingToggle",
                    Label = "Farm Mastery",
                    Action = "farm.mastery.enabled",
                    Setting = "FarmMastery",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Mastery method",
                    Action = "farm.mastery.category.select",
                    Setting = "MasteryCategory",
                    Options = { "Blox Fruit", "Gun" },
                },
                {
                    Kind = "settingSlider",
                    Label = "Mastery health threshold",
                    Action = "farm.mastery.healthPercent.set",
                    Setting = "MasteryHealthPercent",
                    Min = 0,
                    Max = 100,
                    Step = 1,
                    Unit = "%",
                },
                {
                    Kind = "sectionHeader",
                    Label = "Farm Materials",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Farm material",
                    Action = "farm.material.select",
                    Setting = "FarmMaterial",
                    Options = farmMaterials,
                    OptionsProvider = farmMaterialsForCurrentSea,
                    UnavailableSelectionLabel = "Unavailable in this sea",
                    EmptyOptionsLabel = "No materials in this sea",
                },
                {
                    Kind = "settingToggle",
                    Label = "Farm Materials",
                    Action = "farm.material.enabled",
                    Setting = "FarmMaterialsEnabled",
                },
            },
        },
        StackFarming = {
            Title = "Stack Farming",
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Bosses",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack/summon Cake Prince",
                    Action = "stack.cakePrince.enabled",
                    Setting = "AutoAttackCakePrince",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack Elite Hunter",
                    Action = "stack.eliteHunter.enabled",
                    Setting = "AutoEliteHunter",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                },
                {
                    Kind = "settingToggle",
                    Label = "Hop for Elite Hunter",
                    Action = "stack.hop.eliteHunter.enabled",
                    Setting = "HopForEliteHunter",
                    SettingsKey = "StackFarmSettings",
                    ParentSetting = "AutoEliteHunter",
                    RequiredSea = 3,
                    Description = "Requires Auto attack Elite Hunter to be on.",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack/summon Darkbeard",
                    Action = "stack.darkbeard.enabled",
                    Setting = "AttackDarkbeard",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 2,
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack/summon/press pads Rip Indra",
                    Action = "stack.ripIndra.enabled",
                    Setting = "AttackRipIndra",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                },
                {
                    Kind = "settingToggle",
                    Label = "Prioritize Indra if holding God's Chalice",
                    Action = "stack.ripIndra.prioritize",
                    Setting = "PrioritizeRipIndra",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                    Description = "Choose Indra before Dough King when both are enabled.",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack/summon Soul Reaper",
                    Action = "stack.soulReaper.enabled",
                    Setting = "AttackSoulReaper",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto attack/summon Dough King",
                    Action = "stack.doughKing.enabled",
                    Setting = "AttackDoughKing",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                },
                {
                    Kind = "settingToggle",
                    Label = "Prioritize Dough King if holding God's Chalice",
                    Action = "stack.doughKing.prioritize",
                    Setting = "PrioritizeDoughKing",
                    SettingsKey = "StackFarmSettings",
                    RequiredSea = 3,
                    Description = "Choose Dough King before Indra; gather Conjured Cocoa for Sweet Chalice.",
                },
                {
                    Kind = "sectionHeader",
                    Label = "World items",
                },
                {
                    Kind = "settingToggle",
                    Label = "Teleport To Fruit",
                    Action = "stack.fruit.enabled",
                    Setting = "TeleportToFruit",
                    SettingsKey = "StackFarmSettings",
                },
                {
                    Kind = "settingToggle",
                    Label = "Collect Berries",
                    Action = "stack.berry.enabled",
                    Setting = "AutoCollectBerries",
                    SettingsKey = "StackFarmSettings",
                },
                {
                    Kind = "settingToggle",
                    Label = "Hop for berries",
                    Action = "stack.hop.berry.enabled",
                    Setting = "HopForBerries",
                    SettingsKey = "StackFarmSettings",
                    ParentSetting = "AutoCollectBerries",
                    RequiredSea = 3,
                    Description = "Requires Collect Berries to be on.",
                },
            },
        },
        Player = {
            Controls = {
                {
                    Kind = "button",
                    Label = "Character status",
                    Action = "player.status",
                },
            },
        },
        Teleport = {
            SingleColumn = true,
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Island travel",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Island",
                    Action = "teleport.island.select",
                    Setting = "Island",
                    SettingsKey = "TravelSettings",
                    AllowNoSelection = true,
                    PlaceholderLabel = "Choose island",
                    OptionsProvider = travelIslandsForCurrentSea,
                    EmptyOptionsLabel = "No islands available in this sea",
                    UnavailableSelectionLabel = "Unavailable in this sea",
                },
                {
                    Kind = "featureToggle",
                    Label = "Travel to island",
                    Action = "teleport.island",
                },
                {
                    Kind = "sectionHeader",
                    Label = "NPC travel",
                },
                {
                    Kind = "settingDropdown",
                    Label = "NPC",
                    Action = "teleport.npc.select",
                    Setting = "Npc",
                    SettingsKey = "TravelSettings",
                    AllowNoSelection = true,
                    PlaceholderLabel = "Choose NPC",
                    OptionsProvider = travelNpcsForCurrentSea,
                    EmptyOptionsLabel = "No NPCs available in this sea",
                    UnavailableSelectionLabel = "NPC unavailable",
                },
                {
                    Kind = "featureToggle",
                    Label = "Travel to NPC",
                    Action = "teleport.npc",
                },
                {
                    Kind = "button",
                    Label = "Copy NPC availability report",
                    Action = "teleport.npc.report",
                },
            },
        },
        StatusServer = {
            Title = "Server Status",
            SingleColumn = true,
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Status tools",
                },
                {
                    Kind = "button",
                    Label = "Refresh status",
                    Action = "status.refresh",
                },
                {
                    Kind = "button",
                    Label = "Copy status report",
                    Action = "status.copy",
                },
                {
                    Kind = "sectionHeader",
                    Label = "Player",
                },
                { Kind = "statusValue", Key = "sea", Label = "Sea" },
                { Kind = "statusValue", Key = "level", Label = "Level" },
                { Kind = "statusValue", Key = "race", Label = "Race" },
                { Kind = "statusValue", Key = "fragments", Label = "Fragments" },
                { Kind = "statusValue", Key = "money", Label = "Money" },
                {
                    Kind = "sectionHeader",
                    Label = "Farm",
                },
                { Kind = "statusValue", Key = "autoFarm", Label = "Auto Farm" },
                { Kind = "statusValue", Key = "farmMastery", Label = "Farm Mastery" },
                { Kind = "statusValue", Key = "farmMaterials", Label = "Farm Materials" },
                {
                    Kind = "sectionHeader",
                    Label = "Quest",
                },
                { Kind = "statusValue", Key = "questState", Label = "Quest status" },
                { Kind = "statusValue", Key = "questTitle", Label = "Quest" },
                { Kind = "statusValue", Key = "questTarget", Label = "Target" },
                { Kind = "statusValue", Key = "questProgress", Label = "Progress" },
                { Kind = "statusValue", Key = "questReader", Label = "Quest reader" },
                { Kind = "statusValue", Key = "questDialogue", Label = "Quest dialogue" },
                {
                    Kind = "sectionHeader",
                    Label = "Server",
                },
                { Kind = "statusValue", Key = "serverAge", Label = "Server age" },
                { Kind = "statusValue", Key = "players", Label = "Players" },
                { Kind = "statusValue", Key = "placeId", Label = "Place ID" },
                { Kind = "statusValue", Key = "jobId", Label = "Server ID" },
            },
        },
        EventStatus = {
            Title = "Event Status",
            SingleColumn = true,
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Status tools",
                },
                {
                    Kind = "button",
                    Label = "Refresh status",
                    Action = "status.refresh",
                },
                {
                    Kind = "button",
                    Label = "Copy status report",
                    Action = "status.copy",
                },
                {
                    Kind = "sectionHeader",
                    Label = "World events",
                },
                { Kind = "statusValue", Key = "legendaryItemTimer", Label = "Chalice / Fist status" },
                { Kind = "statusValue", Key = "moon", Label = "Moon phase" },
                { Kind = "statusValue", Key = "leviathanSpy", Label = "Leviathan Spy" },
                { Kind = "statusValue", Key = "cakePrinceMobs", Label = "Cake Prince mobs" },
                { Kind = "statusValue", Key = "eliteHunter", Label = "Elite Hunter" },
                { Kind = "statusValue", Key = "mirageIsland", Label = "Mirage Island" },
                { Kind = "statusValue", Key = "prehistoricIsland", Label = "Prehistoric Island" },
                { Kind = "statusValue", Key = "frozenDimension", Label = "Frozen Dimension" },
                { Kind = "statusValue", Key = "tikiEyes", Label = "Tiki eyes" },
            },
        },
        Settings = {
            Title = "Main settings",
            SingleColumn = true,
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Interface",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Team to auto-select",
                    Action = "settings.team.select",
                    Setting = "Team",
                    SettingsKey = "StartupSettings",
                    Options = { "Marines", "Pirates" },
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto Execute",
                    Action = "settings.autoExecute",
                    Setting = "AutoExecute",
                    SettingsKey = "StartupSettings",
                    Description = "Reload Custom Hub after a teleport if your executor supports it.",
                },
                {
                    Kind = "settingDropdown",
                    Label = "UI size",
                    Action = "settings.uiSize.select",
                    Setting = "UiSize",
                    Options = { "Small", "Medium", "Large" },
                },
                {
                    Kind = "settingToggle",
                    Label = "Compact layout",
                    Action = "settings.compact",
                },
                {
                    Kind = "button",
                    Label = "Reset UI settings",
                    Action = "settings.reset",
                },
            },
        },
        FarmSettings = {
            Title = "Farm settings",
            SingleColumn = true,
            Controls = {
                {
                    Kind = "sectionHeader",
                    Label = "Farm options",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Farm weapon",
                    Action = "farm.weaponCategory.select",
                    Setting = "WeaponCategory",
                    Options = weaponCategories,
                },
                {
                    Kind = "settingToggle",
                    Label = "Instant accept quest (RISK)",
                    Action = "farm.settings.instantQuest",
                    Setting = "InstantAcceptQuest",
                },
                {
                    Kind = "settingToggle",
                    Label = "Bring mobs",
                    Action = "farm.settings.bringMobs",
                    Setting = "BringMobs",
                },
                {
                    Kind = "settingSlider",
                    Label = "Bring mob count",
                    Action = "farm.bringMobCount.set",
                    Setting = "BringMobCount",
                    Min = 2,
                    Max = 6,
                    Step = 1,
                    Unit = "mobs",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto turn on Buso",
                    Action = "farm.settings.autoBuso",
                    Setting = "AutoBuso",
                },
            },
        },
    },
}

for settingName, defaultValue in pairs(farmSkillDefaults) do
    if Config.FarmSettings[settingName] == nil then
        Config.FarmSettings[settingName] = defaultValue
    end
end
for _, control in ipairs(farmSkillControls) do
    table.insert(Config.Pages.FarmSettings.Controls, control)
end

return Config
