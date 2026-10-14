from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text()
STATE = (ROOT / "src/ReplicatedStorage/CustomHub/State.lua").read_text()
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text()
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/StatusFeature.lua").read_text()
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text()
QUEST_SERVICE = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/QuestService.lua"
).read_text()


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


require(
    '"StatusServer"' in CONFIG
    and 'Title = "Server Status"' in CONFIG
    and 'tabName == "StatusServer" and "Server Status"' in UI
    and 'Settings = {\n            { Label = "Event Status", Page = "EventStatus" }' in CONFIG
    and 'EventStatus = {\n            Title = "Event Status"' in CONFIG
    and 'Action = "status.refresh"' in CONFIG
    and 'Action = "status.copy"' in CONFIG,
    "Server Status remains top-level and Event Status is the Settings default subpage",
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
    and "function readWorldEventValues(context, statusFeature)" in FEATURE
    and 'location:GetAttribute("TimeIn")' in FEATURE
    and "workspace:GetServerTimeNow()" in FEATURE
    and "tick() - 25200" in FEATURE
    and "function updateMoonClockRate(statusFeature, clockTime)" in FEATURE
    and "elapsed >= 8" in FEATURE
    and "local function moonForecast(phaseText, clockTime)" in FEATURE
    and 'return "Full Moon ends in", 5 - clockTime' in FEATURE
    and 'return "Next Full Moon in", targetClock - clockTime' in FEATURE
    and 'local function formatMoonEstimate(realSeconds)' in FEATURE
    and '"game clock "' not in FEATURE
    and '" (estimate)"' in FEATURE
    and "ELITE_TARGET_NAMES" in FEATURE,
    "Event Status estimates moon timing from measured real clock speed and omits raid countdowns",
)
require(
    "function StatusFeature:_ReadValues()" in FEATURE
    and "function StatusFeature:_BuildReport(values)" in FEATURE
    and 'values.fullJobId' in FEATURE
    and 'context.State:SetStatusValues(self:_ReadValues())' in FEATURE
    and 'InvokeServer("InfoLeviathan", "1")' in FEATURE
    and 'InvokeServer("CakePrinceSpawner", true)' in FEATURE
    and 'InvokeServer("CakePrinceSpawner")' not in FEATURE
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
