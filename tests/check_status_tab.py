from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text()
STATE = (ROOT / "src/ReplicatedStorage/CustomHub/State.lua").read_text()
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text()
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/StatusFeature.lua").read_text()
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text()
STANDALONE_UI_TEST = (ROOT / "tests/Standalone_CustomHub_UI_Test.client.lua").read_text()
TOP_LEVEL_TABS = CONFIG.split("    Tabs = {", 1)[1].split("    TabSubsections =", 1)[0]
SUBSECTIONS = CONFIG.split("    TabSubsections = {", 1)[1].split("    CollapsibleDefaults", 1)[0]
STATUS_SUBSECTIONS = SUBSECTIONS.split("        Status = {", 1)[1].split("        Settings = {", 1)[0]
SETTINGS_SUBSECTIONS = SUBSECTIONS.split("        Settings = {", 1)[1]
QUEST_SERVICE = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/QuestService.lua"
).read_text()


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


require(
    '"Status",' in TOP_LEVEL_TABS
    and '"StatusServer"' not in TOP_LEVEL_TABS
    and 'Title = "Server Status"' in CONFIG
    and 'tabName == "StatusServer" and "Server Status"' in UI
    and STATUS_SUBSECTIONS.index('Label = "Event Status"')
        < STATUS_SUBSECTIONS.index('Label = "Server Status"')
    and 'Page = "EventStatus"' in STATUS_SUBSECTIONS
    and 'Page = "StatusServer"' in STATUS_SUBSECTIONS
    and 'Label = "Main settings", Page = "Settings"' in SETTINGS_SUBSECTIONS
    and "Event Status" not in SETTINGS_SUBSECTIONS
    and 'EventStatus = {\n            Title = "Event Status"' in CONFIG
    and 'Action = "status.refresh"' in CONFIG
    and 'Action = "status.copy"' in CONFIG
    and 'local Tabs = { "Main", "Farm", "Player", "Teleport", "Status", "Settings" }' in STANDALONE_UI_TEST
    and 'Status = {\n        Controls = {' in STANDALONE_UI_TEST,
    "Status is a top-level tab with Event Status first and Server Status second",
)
require(
    'Kind = "statusValue"' in CONFIG
    and "statusValues = statusValues" in STATE
    and "function State:SetStatusValues(values)" in STATE
    and "snapshot.statusValues[entry.Key]" in UI,
    "status rows update from isolated state snapshots",
)
require(
    all(
        f'Key = "{key}"' in CONFIG
        for key in (
            "fragments",
            "money",
            "questState",
            "questTitle",
            "questTarget",
            "questProgress",
            "questReader",
            "questDialogue",
        )
    )
    and "function QuestService:GetActiveQuestDetails()" in QUEST_SERVICE
    and "self:GetActiveQuestState()" in QUEST_SERVICE
    and "parseTrackedQuestProgress" in QUEST_SERVICE
    and "titleContainsTarget(title, targetName, true)" in QUEST_SERVICE,
    "Server Status replaces health/alive with currency and reuses validated quest details",
)
require(
    all(
        f'Key = "{key}"' in CONFIG
        for key in (
            "serverAge",
            "legendaryItemTimer",
            "moon",
            "leviathanSpy",
            "cakePrinceMobs",
            "eliteHunter",
            "mirageIsland",
            "prehistoricIsland",
            "frozenDimension",
            "tikiEyes",
        )
    )
    and "raidTimer" not in CONFIG
    and "prehistoricTimer" not in CONFIG
    and '"Health"' not in CONFIG
    and '"Character"' not in CONFIG
    and 'Label = "Chalice / Fist status"' in CONFIG
    and "function readWorldEventValues(context, statusFeature)" in FEATURE
    and 'location:GetAttribute("TimeIn")' in FEATURE
    and "workspace:GetServerTimeNow()" in FEATURE
    and "tick() - 25200" in FEATURE
    and "local function readLegendaryItemStatus(context, workspace, elapsed)" in FEATURE
    and '"Chest window active; next cycle in "' in FEATURE
    and 'itemName .. " held by "' in FEATURE
    and "Fist of Darkness" in FEATURE
    and "Used: " in FEATURE
    and "function updateMoonClockRate(statusFeature, clockTime)" in FEATURE
    and "elapsed >= 8" in FEATURE
    and "local function moonForecast(phaseText, clockTime, phaseNumber)" in FEATURE
    and "Phase %d (%d nights until Full Moon)" in FEATURE
    and 'return "Full Moon ends in", 5 - clockTime' in FEATURE
    and 'return "Next Full Moon in", targetClock - clockTime' in FEATURE
    and 'local function formatMoonEstimate(realSeconds)' in FEATURE
    and '"game clock "' not in FEATURE
    and '" | no timing estimate"' not in FEATURE
    and '" (estimate)"' in FEATURE
    and "ELITE_TARGET_NAMES" in FEATURE
    and '"Not spawned"' in FEATURE
    and '"Not spawned (template loaded: "' in FEATURE
    and "function readTikiEyes(map)" in FEATURE
    and 'return "0 / 4 cleared"' in FEATURE
    and 'Eye" .. tostring(index)' in FEATURE
    and "return value and \"Spawned\" or \"Not spawned\"" in FEATURE
    and "Third Sea only" in FEATURE
    and 'gsub("<[^>]+>", "")' in FEATURE,
    "Event Status distinguishes found items, reports moon phases and estimates, and labels absent events consistently",
)
require(
    "function StatusFeature:_ReadValues()" in FEATURE
    and "function StatusFeature:_BuildReport(values)" in FEATURE
    and 'values.fullJobId' in FEATURE
    and 'context.State:SetStatusValues(self:_ReadValues())' in FEATURE
    and 'InvokeServer("InfoLeviathan", "1")' in FEATURE
    and 'InvokeServer("CakePrinceSpawner", true)' in FEATURE
    and 'InvokeServer("CakePrinceSpawner")' not in FEATURE
    and '"Leviathan is out"' in FEATURE
    and '"I DONT KNOW"' in FEATURE
    and '"Bribe the Spy"' in FEATURE
    and "enemies left" in FEATURE
    and 'string.find(normalized, "open the portal", 1, true)' in FEATURE
    and "StatusFeature" in MANAGER,
    "event status uses only the references' read-only remote queries and never triggers Cake Prince",
)
require(
    'snapshot.selectedTab == "StatusServer"' in FEATURE
    and 'snapshot.selectedTab == "EventStatus"' in FEATURE
    and "now - (self._lastRemoteRefreshAt or -math.huge) < 15" in FEATURE
    and "task.wait(1)" in FEATURE
    and "self._generation = (self._generation or 0) + 1" in FEATURE,
    "local status refreshes only on the two status pages and remote checks are rate-limited",
)
require(
    "StatusValueEntries" in UI
    and 'control.Kind == "statusValue"' in UI
    and "Name = self:_ControlNodeName(control)" in UI,
    "status rows use the existing hub card style and refresh lifecycle",
)
