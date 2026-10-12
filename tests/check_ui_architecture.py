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
    "Background = Color3.fromRGB(17, 19, 25)",
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
    and "visibleHeaderHeight - HEADER_HEIGHT + halfY" in window_drag_helper
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

require("RowHeight = 40" in CONFIG, "production control rows should stay compact")
require("MobileWidth = 0.98" in CONFIG
        and "ExpandedWidth = 0.98" in CONFIG
        and "MaxSize = Vector2.new(920, 740)" in CONFIG
        and "SidebarMaxWidth = 224" in CONFIG,
        "landscape panel sizing should match the reference footprint")
require("landscape and 370 or 320" in UI_MODULE,
        "landscape panel should retain the larger reference-height footprint")
require('Name = "PageDescription"' not in UI_MODULE
        and 'Name = "SectionHeader"' not in UI_MODULE
        and 'Name = "Detail"' not in UI_MODULE,
        "redundant page and control subheadings should not be rendered")
require("SelectorOptionsTop = 6" in CONFIG
        and "SelectorOptionsHeight = 28" in CONFIG
        and "SelectorTitleWidth = 120" in CONFIG,
        "compact selector options are not aligned inside the control row")
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
print("PASS: five tabs, UI-only actions, and local cleanup lifecycle")
print("PASS: client self-test and manual-inspection reporting hooks")
print("PASS: no remotes, dynamic loading, or executor-only APIs")
print("PASS: documentation and whitespace checks")
