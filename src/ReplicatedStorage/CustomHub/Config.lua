local weaponCategories = { "Melee", "Sword", "Blox Fruit" }
local farmModes = {
    "Level Farm",
    "Aura Farm",
    "Farm Bones",
    "Farm Cake Prince",
    "Farm Tyrant of the Skies",
}
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
        Groups = { "farmSettings" },
    },
    {
        Kind = "settingToggle",
        Label = "Use skills while farming",
        Action = "farm.skills.enabled",
        Setting = "UseFarmSkills",
        Groups = { "farmSettings" },
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
        Groups = { "farmSettings" },
    },
    {
        Kind = "settingToggle",
        Label = "Fast skill release",
        Action = "farm.skills.fastRelease",
        Setting = "FarmSkillFastRelease",
        Groups = { "farmSettings" },
    },
    {
        Kind = "collapsibleHeader",
        Label = "Available skill keys",
        GroupId = "farmSkillKeys",
        Groups = { "farmSettings" },
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
            Groups = { "farmSettings", "farmSkillKeys" },
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
            { Label = "UI settings" },
            { Label = "Farm settings", GroupId = "farmSettings" },
        },
    },
    CollapsibleDefaults = {
        farmSettings = true,
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
                {
                    Kind = "collapsibleHeader",
                    Label = "Farm settings",
                    GroupId = "farmSettings",
                },
                {
                    Kind = "settingDropdown",
                    Label = "Farm weapon",
                    Action = "farm.weaponCategory.select",
                    Setting = "WeaponCategory",
                    Options = weaponCategories,
                    Groups = { "farmSettings" },
                },
                {
                    Kind = "settingToggle",
                    Label = "Bring mobs",
                    Action = "farm.settings.bringMobs",
                    Setting = "BringMobs",
                    Groups = { "farmSettings" },
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
                    Groups = { "farmSettings" },
                },
                {
                    Kind = "settingToggle",
                    Label = "Auto turn on Buso",
                    Action = "farm.settings.autoBuso",
                    Setting = "AutoBuso",
                    Groups = { "farmSettings" },
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
    table.insert(Config.Pages.Settings.Controls, control)
end

return Config
