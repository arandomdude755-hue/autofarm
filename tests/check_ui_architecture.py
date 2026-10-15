import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = "tests/Standalone_CustomHub_UI_Test.client.lua"
SCRIPT = (ROOT / SCRIPT_PATH).read_text(encoding="utf-8")
UI_MODULE_PATH = "src/ReplicatedStorage/CustomHub/UI.lua"
UI_MODULE = (ROOT / UI_MODULE_PATH).read_text(encoding="utf-8")
CONFIG_PATH = "src/ReplicatedStorage/CustomHub/Config.lua"
CONFIG = (ROOT / CONFIG_PATH).read_text(encoding="utf-8")
STATE = (ROOT / "src/ReplicatedStorage/CustomHub/State.lua").read_text(encoding="utf-8")
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text(encoding="utf-8")
DOCS = (ROOT / "docs/BNN_SOURCE_INVENTORY.md").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
require(project["name"] == "CustomHubMobileUiTest", "Standalone Rojo project name missing")
entry = project["tree"]["StarterPlayer"]["StarterPlayerScripts"]["CustomHubMobileUiTest.client.lua"]
require(entry["$path"] == SCRIPT_PATH, "Rojo mapping does not point to the standalone LocalScript")
require("ReplicatedStorage" not in project["tree"], "Standalone project should not depend on modules")

for tab in ("Main", "Farm", "Player", "Teleport", "Settings"):
    require(f"{tab} = {{" in SCRIPT, f"Standalone page is missing: {tab}")
    require(f'"{tab}"' in CONFIG, f"production UI is missing the {tab} tab")

for token in (
    "Background = Color3.fromRGB(12, 14, 19)",
    "Header = Color3.fromRGB(21, 25, 34)",
    "TabBar = Color3.fromRGB(13, 16, 22)",
    "Control = Color3.fromRGB(22, 26, 36)",
    "Accent = Color3.fromRGB(59, 130, 246)",
):
    require(token in CONFIG, f"production theme diverged from standalone reference: {token}")

for token in (
    'Name = "ActiveMarker"',
    'Name = "Sidebar"',
    'Name = "SearchInput"',
    'Name = "Navigation"',
    'Name = "MainPane"',
    'Name = "PageHeader"',
    'Name = "SearchHandle"',
    'Name = "Label"',
    'Name = "PulseHalo"',
    'function UI:_AttachButtonFeedback',
    'function UI:_ApplySearchFilter()',
    'PlaceholderText = "Search..."',
    'sidebarWidth < 214',
    'or "Search section or function"',
    "self.Root.Position = clampWindowDragPosition(",
    "landscape and 56 or 32",
    'Position = UDim2.new(0, 28, 0, 0)',
):
    require(token in UI_MODULE, f"production UI is missing a referenced design/interaction component: {token}")

window_drag_start = UI_MODULE.index("local function clampWindowDragPosition")
window_drag_end = UI_MODULE.index("\nlocal function disconnectAll", window_drag_start)
window_drag_helper = UI_MODULE[window_drag_start:window_drag_end]
require(
    "WINDOW_VISIBLE_GRIP_WIDTH = 128" in UI_MODULE
    and "WINDOW_VISIBLE_GRIP_HEIGHT = 24" in UI_MODULE
    and "visibleGripWidth - halfX" in window_drag_helper
    and "viewport.X - visibleGripWidth + halfX" in window_drag_helper
    and "visibleHeaderHeight - headerExtent + halfY" in window_drag_helper
    and "viewport.Y - visibleHeaderHeight + halfY" in window_drag_helper,
    "window dragging must allow partial off-screen movement while keeping a header grip visible",
)
size_start = UI_MODULE.index("function UI:_ApplySize")
size_end = UI_MODULE.index("\nfunction UI:_SetMinimized", size_start)
size_method = UI_MODULE[size_start:size_end]
require(
    "self.RestoreButton.Position = clampDragPosition(" in UI_MODULE
    and "self.Root.Size = UDim2.fromOffset(math.floor(width), math.floor(height))"
    in size_method
    and size_method.index("self.Root.Size =") < size_method.index("self:_ClampWindow()"),
    "the restore button should stay fully visible and resized windows should retain a reachable header",
)

require("RowHeight = 42" in CONFIG, "production control rows should keep a comfortable tap height")
group_builder_start = UI_MODULE.index("function UI:_CreateControlGroup")
group_builder_end = UI_MODULE.index("\nfunction UI:_RenderTab", group_builder_start)
group_builder = UI_MODULE[group_builder_start:group_builder_end]
render_tab_start = UI_MODULE.index("function UI:_RenderTab")
render_tab_end = UI_MODULE.index("\nfunction UI:Mount", render_tab_start)
render_tab = UI_MODULE[render_tab_start:render_tab_end]
control_builder_start = UI_MODULE.index("function UI:_AddControl")
control_builder_end = UI_MODULE.index("\nfunction UI:_CreateControlGroup", control_builder_start)
control_builder = UI_MODULE[control_builder_start:control_builder_end]
require(
    "SectionHeaderHeight = 42" in CONFIG
    and 'Name = cardName .. "_Card"' in group_builder
    and 'Name = "SectionTitle"' in group_builder
    and 'Name = "SectionHeaderBand"' in group_builder
    and 'Name = "SectionIconDot"' in group_builder
    and 'Name = "SectionDivider"' in group_builder
    and "group.Stroke = create(\"UIStroke\"" in group_builder
    and 'Name = "ActionIndicator"' in control_builder
    and 'create("UIListLayout"' in render_tab
    and 'if control.Kind == "sectionHeader" then' in render_tab
    and 'self:_AddControl(control, group.ControlsFrame)' in render_tab
    and "BackgroundTransparency = 0.18" in control_builder
    and "create(\"UIStroke\"" in control_builder
    and "Name = \"GroupArrow\"" in control_builder,
    "section cards should use a clear blue-accent header with surfaced controls and working skill-key collapse",
)
require("MobileWidth = 0.86" in CONFIG
        and "ExpandedWidth = 0.98" in CONFIG
        and "MaxSize = Vector2.new(920, 740)" in CONFIG
        and "SidebarMaxWidth = 224" in CONFIG,
        "landscape panel sizing should match the reference footprint")
require("MinSize = Vector2.new(280, 320)" in CONFIG
        and "local availableHeight = math.max(1, viewport.Y - verticalInset)" in UI_MODULE
        and "math.min(landscape and 420 or 740, availableHeight)" in UI_MODULE
        and "group.ControlsFrame.AbsoluteSize.X >= 620" in UI_MODULE,
        "small and medium sizes should keep a usable minimum while respecting viewport height and responsive columns")
require("SidebarNavInsetTop = 4" in CONFIG
        and "local top = layout.SidebarNavInsetTop" in UI_MODULE
        and "local navTop = layout.SidebarNavInsetTop" in UI_MODULE
        and "SidebarNavInsetLeft = 5" in CONFIG
        and "UDim2.fromOffset(layout.SidebarNavInsetLeft, top)" in UI_MODULE
        and "UDim2.fromOffset(layout.SidebarNavInsetLeft, navTop)" in UI_MODULE
        and "layout.SidebarNavInsetLeft * 2" in UI_MODULE,
        "navigation rows need top and side insets so selected outlines are not clipped")
pages_start = CONFIG.index("Pages = {")
settings_start = CONFIG.index("        Settings = {", pages_start)
farm_settings_start = CONFIG.index("        FarmSettings = {", settings_start)
pages_end = CONFIG.index("\n    },\n}\n\nfor settingName", farm_settings_start)
settings_page = CONFIG[settings_start:farm_settings_start]
farm_settings_page = CONFIG[farm_settings_start:pages_end]
require('Label = "UI size"' in settings_page
        and 'Kind = "settingDropdown"' in settings_page
        and 'Action = "settings.uiSize.select"' in settings_page
        and 'Setting = "UiSize"' in settings_page
        and 'Options = { "Small", "Medium", "Large" }' in settings_page
        and 'Label = "Compact layout"' in settings_page
        and 'Label = "Reset UI settings"' in settings_page
        and 'Label = "Farm weapon"' not in settings_page,
        "Main settings must contain UI controls only, not Farm settings")
require('Title = "Farm settings"' in farm_settings_page
        and 'SingleColumn = true' in farm_settings_page
        and 'Label = "Farm weapon"' in farm_settings_page
        and 'Label = "Bring mobs"' in farm_settings_page
        and 'Label = "Auto turn on Buso"' in farm_settings_page
        and 'Kind = "collapsibleHeader"' not in farm_settings_page,
        "Farm settings must have its own page instead of a nested section on Main settings")
require('Label = "Combat skills"' in CONFIG
        and 'Label = "Available skill keys"' in CONFIG
        and 'GroupId = "farmSkillKeys"' in CONFIG
        and 'Groups = { "farmSkillKeys" }' in CONFIG
        and 'function UI:_IsControlVisible(control)' in UI_MODULE
        and 'function UI:_SetControlGroupExpanded(groupId, expanded)' in UI_MODULE
        and 'function UI:_ExpandMatchingControlGroups()' in UI_MODULE
        and 'self:_ExpandMatchingControlGroups()' in UI_MODULE
        and 'self.ControlRows[control] = row' in UI_MODULE,
        "Combat skill headings must be retained while skill-key controls collapse in the page flow")
require('TabSubsections = {' in CONFIG
        and 'Settings = {' in CONFIG
        and '{ Label = "Main settings", Page = "Settings" }' in CONFIG
        and '{ Label = "Farm settings", Page = "FarmSettings" }' in CONFIG
        and 'function UI:_LayoutNavigation(animate)' in UI_MODULE
        and 'function UI:_SelectSubsection(tabName, subsection)' in UI_MODULE
        and 'self:_SelectSubsection(tabName, subsections[1])' in UI_MODULE
        and 'tabName == snapshot.selectedTab or tabName == selectedParent' in UI_MODULE
        and 'self.ExpandedTabs[expandedTab] = expandedTab == parentTab' in UI_MODULE
        and 'top = top + layout.SidebarChildRowHeight + layout.SidebarRowGap' in UI_MODULE
        and 'self.NavScroll.CanvasSize = UDim2.new(' in UI_MODULE,
        "Settings sidebar children must reflow the following tabs instead of overlaying them")
require('UiSize = "Large"' in CONFIG
        and "Small = 0.88" in CONFIG
        and "Medium = 0.94" in CONFIG
        and "Large = 1" in CONFIG
        and "UiSizeFootprints" in CONFIG
        and "MinUsableWidth = 328" in CONFIG
        and "self.RootScale = create(\"UIScale\"" in UI_MODULE
        and "self.RootScale.Scale = 1" in size_method
        and "self.RootScale.Scale = sizeScale" not in size_method
        and "math.min(viewport.X * widthScale * footprint, maxWidth)" in size_method,
        "UI size options should resize the window footprint without shrinking text or touch targets")
require(
    "ScrollBottomPadding = 28" in CONFIG
    and "local contentTop = self.Content and self.Content.Position.Y.Offset or 0" in UI_MODULE
    and "local bottomPadding = layout.ScrollBottomPadding or 28" in UI_MODULE
    and "self.ContentLayout.AbsoluteContentSize.Y" in UI_MODULE
    and "contentTop + self.ContentLayout.AbsoluteContentSize.Y" in UI_MODULE,
    "page scrolling should leave a clear bottom margin after the final card",
)
require("function State:SetUiSize(size)" in STATE
        and "uiSize = self._values.uiSize" in STATE
        and "uiSize = self._defaults.UiSize" in STATE
        and 'actionId == "settings.uiSize.select"' in MANAGER
        and "layout.UiSizeFootprints" in MANAGER
        and "self.State:SetUiSize(payload)" in MANAGER,
        "UI size selection must update state and reset to its default")
require("Compact = false" in CONFIG,
        "default sizing should use the large panel while compact mode stays opt-in")
require('Name = "PageDescription"' not in UI_MODULE
        and 'Name = "SectionHeader"' not in UI_MODULE
        and 'Name = "Detail"' not in UI_MODULE,
        "redundant page and control subheadings should not be rendered")
require("local anchor = entry.Row or entry.Button" in UI_MODULE
        and "local left = (anchorPosition.X - rootPosition.X) / scale" in UI_MODULE
        and "local menuWidth = anchorSize.X / scale" in UI_MODULE
        and "local rootHeight = rootSize.Y / scale" in UI_MODULE
        and "local belowAvailable = math.max(0, rootHeight - belowTop - 8)" in UI_MODULE
        and "local aboveAvailable = math.max(0, anchorTop - 8)" in UI_MODULE
        and "local openBelow = belowAvailable >= totalHeight" in UI_MODULE
        and "or belowAvailable >= aboveAvailable" in UI_MODULE
        and "math.max(8, anchorTop - menuHeight - 4)" in UI_MODULE
        and "local availableHeight = openBelow and belowAvailable or aboveAvailable" in UI_MODULE
        and 'local row = create((isSelector or isSlider) and "Frame" or "TextButton"' in UI_MODULE
        and "Button = row" in UI_MODULE
        and "}, self.Root)" in UI_MODULE
        and "}, overlay)" in UI_MODULE
        and "Position = UDim2.fromOffset(0, y)" in UI_MODULE
        and "y += optionHeight" in UI_MODULE
        and "Size = UDim2.new(1, 0, 0, optionHeight)" in UI_MODULE
        and "DropdownOptionHeight = 44" in CONFIG
        and "TextSize = 13" in UI_MODULE
        and 'local selectedValue = control.Setting == "UiSize"' in UI_MODULE
        and "Row = row" in UI_MODULE
        and 'Name = "DropdownFace"' in UI_MODULE
        and 'Name = "DropdownArrowDivider"' in UI_MODULE
        and "DropdownArrowWidth + 2" in UI_MODULE
        and "TextXAlignment = Enum.TextXAlignment.Left" in UI_MODULE
        and "function UI:_SetDropdownOpenVisual(entry, isOpen)" in UI_MODULE
        and "DropdownWidthRatio = 0.5" in CONFIG,
        "dropdowns must open below their full-width selector row, show the current value in a clear field, and keep the arrow separate")
require(
    "ToggleValueWidth = 68" in CONFIG
    and 'Name = "SwitchTrack"' in UI_MODULE
    and 'Name = "SwitchThumb"' in UI_MODULE
    and "entry.Track.BackgroundColor3 = enabled and theme.Accent or theme.TabBar" in UI_MODULE,
    "toggle controls should show a readable state beside a compact switch",
)
require('Name = "SectionHeader"' not in SCRIPT
        and 'Name = "Detail"' not in SCRIPT
        and "Temporary UI test row" not in SCRIPT,
        "standalone UI reference still renders redundant subheadings")

require(not re.search(r"\brequire\s*\(", SCRIPT), "Standalone script must not import modules")
require("Players.LocalPlayer" in SCRIPT and 'WaitForChild("PlayerGui"' in SCRIPT,
        "Standalone script must mount in the local player's GUI")
require("BindableFunction" in SCRIPT and "previousCleanup:Invoke()" in SCRIPT,
        "Safe rerun cleanup registry is missing")
require("script.Destroying" in SCRIPT and "closeButton.Activated" in SCRIPT,
        "LocalScript/Close cleanup path is missing")
require("connection:Disconnect()" in SCRIPT, "Explicit connection cleanup is missing")

for token in (
    'Name = "Minimize"',
    'Text = "−"',
    'Name = "Restore"',
    'Text = "⌂"',
    "function UI:_SetMinimized(minimized)",
    "self.Root.Visible = not minimized",
    "self.RestoreButton.Visible = minimized",
    "self.RestoreButton.Position = clampDragPosition(",
    "UserInputService.InputChanged",
    "UserInputService.InputEnded",
):
    require(token in UI_MODULE, f"production UI minimize/restore path is missing: {token}")

require(UI_MODULE.count('Name = "Minimize"') == 1,
        "production UI creates duplicate minimize buttons")
require(UI_MODULE.count('Name = "Restore"') == 1,
        "production UI creates duplicate restore buttons")
require(UI_MODULE.count("UserInputService.InputChanged") == 1
        and UI_MODULE.count("UserInputService.InputEnded") == 1,
        "restore drag input listeners are duplicated")
minimize_start = UI_MODULE.index("function UI:_SetMinimized(minimized)")
minimize_end = UI_MODULE.index("\nfunction UI:_Refresh", minimize_start)
minimize_method = UI_MODULE[minimize_start:minimize_end]
require("create(" not in minimize_method and "_Connect(" not in minimize_method,
        "minimize/restore toggles create UI or event connections")
close_handler_start = UI_MODULE.index(
    "self:_Connect(self.PersistentConnections, closeButton.Activated"
)
close_handler_end = UI_MODULE.index("\n\n", close_handler_start)
require("self.OnClose()" in UI_MODULE[close_handler_start:close_handler_end],
        "existing close button no longer calls the original close callback")

for marker in (
    "tab selection and active indicators",
    "farm preview changes local state only",
    "compact setting updates and restores window size",
    "compact control rows",
    "placeholder actions only update status",
    "tab text and toggle title fit current viewport",
    "scroll view supports overflow",
    "cleanup removes UI and disconnects connections",
    "replacement mount does not duplicate the interface",
    "MANUAL: tap all tabs and Close",
):
    require(marker in SCRIPT, f"Standalone client checks are missing: {marker}")

for forbidden in (
    "InvokeServer",
    "FireServer",
    "RemoteEvent",
    "RemoteFunction",
    "loadstring",
    "getgenv",
    "VirtualInputManager",
    "HttpGet",
):
    require(forbidden not in SCRIPT, f"Forbidden game/executor integration found: {forbidden}")

require(SCRIPT_PATH in DOCS, "Standalone launch documentation is missing")
require("CustomHubStudioSmokeTests" not in DOCS, "Old Studio-only test instructions remain")
require("copy the entire file" in DOCS.lower(), "Copy/paste launch steps are missing")

for path in [
    ROOT / "default.project.json",
    ROOT / SCRIPT_PATH,
    ROOT / "tests/check_ui_architecture.py",
    ROOT / "docs/BNN_SOURCE_INVENTORY.md",
    ROOT / UI_MODULE_PATH,
    ROOT / CONFIG_PATH,
]:
    text = path.read_text(encoding="utf-8")
    require(all(line == line.rstrip() for line in text.splitlines()),
            f"Trailing whitespace: {path.relative_to(ROOT)}")

print("PASS: standalone Rojo mapping and no-module packaging")
print("PASS: six tabs, UI-only actions, and local cleanup lifecycle")
print("PASS: client self-test and manual-inspection reporting hooks")
print("PASS: no remotes, dynamic loading, or executor-only APIs")
print("PASS: documentation and whitespace checks")
