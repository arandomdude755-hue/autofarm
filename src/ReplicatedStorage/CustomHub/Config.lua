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
    Defaults = {
        SelectedTab = "Main",
        Compact = false,
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
        AutoBuso = false,
        UseFarmSkills = false,
        FarmSkillHoldSeconds = 0.5,
        FarmSkillFastRelease = false,
        -- An unset BNN setting follows its animated, CanAttack-validated branch.
        AttackNoAnimation = false,
    },
    Layout = {
        MobileWidth = 0.86,
        MobileHeight = 0.78,
        DesktopWidth = 0.72,
        DesktopHeight = 0.78,
        ExpandedWidth = 0.98,
        ExpandedHeight = 0.88,
        UiSizeScales = {
            Small = 0.82,
            Medium = 0.91,
            Large = 1,
        },
        MinSize = Vector2.new(280, 370),
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
        PageHeaderHeight = 32,
        StatusTop = 0,
        StatusHeight = 30,
        StatusInset = 8,
        StatusTextTop = 0,
        ScrollContentInset = 18,
        ScrollBarThickness = 3,
        RowHeight = 40,
        RowInset = 10,
        RowTitleTop = 0,
        RowTitleHeight = 40,
        SelectorTitleTop = 0,
        SelectorTitleHeight = 40,
        SelectorTitleWidth = 120,
        SelectorTitleGap = 8,
        SelectorOptionsTop = 6,
        SelectorOptionsHeight = 28,
        DropdownWidthRatio = 0.42,
        DropdownTitleGap = 8,
        DropdownHeight = 29,
        DropdownValueInset = 10,
        DropdownArrowWidth = 32,
        DropdownArrowInset = 3,
        DropdownOptionHeight = 44,
        SliderTitleHeight = 22,
        SliderTrackTop = 27,
        SliderTrackHeight = 6,
        SliderValueWidth = 72,
        ToggleValueTop = 9,
        ToggleValueWidth = 52,
        ToggleValueHeight = 20,
        ToggleGap = 7,
        Spacing = 6,
        Padding = 8,
        BorderThickness = 1,
    },
    Theme = {
        Background = Color3.fromRGB(17, 19, 25),
        Header = Color3.fromRGB(21, 25, 34),
        TabBar = Color3.fromRGB(13, 16, 22),
        Panel = Color3.fromRGB(18, 21, 29),
        Sidebar = Color3.fromRGB(15, 18, 24),
        Control = Color3.fromRGB(22, 26, 36),
        Selected = Color3.fromRGB(23, 29, 41),
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
        "Settings",
    },
    TabSubsections = {
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
            Controls = {
                {
                    Kind = "settingDropdown",
                    Label = "Farm method",
                    Action = "farm.mode.select",
                    Setting = "FarmMode",
                    Options = farmModes,
                },
                {
                    Kind = "settingDropdown",
                    Label = "Farm material",
                    Action = "farm.material.select",
                    Setting = "FarmMaterial",
                    Options = farmMaterials,
                },
                {
                    Kind = "settingToggle",
                    Label = "Farm Materials",
                    Action = "farm.material.enabled",
                    Setting = "FarmMaterialsEnabled",
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto quest for modes",
                    Action = "farm.autoModeQuest",
                    Setting = "AutoModeQuest",
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
                    Kind = "button",
                    Label = "Copy status report",
                    Action = "farm.status.copy",
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
            Controls = {
                {
                    Kind = "button",
                    Label = "Travel status",
                    Action = "teleport.status",
                },
            },
        },
        Settings = {
            Title = "Main settings",
            SingleColumn = true,
            Controls = {
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
                    Kind = "settingDropdown",
                    Label = "Farm weapon",
                    Action = "farm.weaponCategory.select",
                    Setting = "WeaponCategory",
                    Options = weaponCategories,
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
