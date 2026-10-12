local weaponCategories = { "Melee", "Sword", "Blox Fruit" }

local Config = {
    Name = "Custom Hub",
    Version = "UI shell",
    Defaults = {
        SelectedTab = "Main",
        Compact = true,
        StatusMaxCharacters = 88,
    },
    FarmSettings = {
        -- Mirrors BNN's `Settings["Select Weapon"] or "Melee"` default.
        WeaponCategories = weaponCategories,
        WeaponCategory = "Melee",
        -- An unset BNN setting follows its animated, CanAttack-validated branch.
        AttackNoAnimation = false,
    },
    Layout = {
        MobileWidth = 0.92,
        MobileHeight = 0.78,
        DesktopWidth = 0.72,
        DesktopHeight = 0.78,
        ExpandedWidth = 0.96,
        ExpandedHeight = 0.88,
        MinSize = Vector2.new(280, 300),
        MaxSize = Vector2.new(760, 740),
        HeaderTop = 7,
        HeaderHeight = 40,
        CloseWidth = 28,
        CloseHeight = 26,
        TitleRightInset = 84,
        SidebarWidthRatio = 0.25,
        SidebarMinWidth = 88,
        SidebarMaxWidth = 192,
        MainPaneMinWidth = 180,
        SidebarSearchHeight = 30,
        SidebarSearchInset = 8,
        SidebarNavTop = 46,
        SidebarRowHeight = 30,
        SidebarRowGap = 3,
        PageHeaderHeight = 32,
        StatusTop = 0,
        StatusHeight = 30,
        StatusInset = 8,
        StatusTextTop = 0,
        ScrollContentInset = 18,
        ScrollBarThickness = 3,
        RowHeight = 48,
        RowInset = 10,
        RowTitleTop = 0,
        RowTitleHeight = 48,
        SelectorTitleTop = 0,
        SelectorTitleHeight = 48,
        SelectorTitleWidth = 120,
        SelectorTitleGap = 8,
        SelectorOptionsTop = 8,
        SelectorOptionsHeight = 32,
        ToggleValueTop = 10,
        ToggleValueWidth = 58,
        ToggleValueHeight = 22,
        ToggleGap = 8,
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
            Control = 13,
            Body = 12,
            Tab = 10,
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
                    Kind = "featureToggle",
                    Label = "Auto Farm Level",
                    Action = "farm.main",
                },
                {
                    Kind = "button",
                    Label = "Copy status report",
                    Action = "farm.status.copy",
                },
                {
                    Kind = "settingSelect",
                    Label = "Weapon category",
                    Action = "farm.weaponCategory.select",
                    Setting = "WeaponCategory",
                    Options = weaponCategories,
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
            Controls = {
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
    },
}

return Config
