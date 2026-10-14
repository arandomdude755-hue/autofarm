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
    and 'Title = "Status & Server"' in CONFIG
    and 'tabName == "StatusServer" and "Status"' in UI
    and 'Action = "status.refresh"' in CONFIG
    and 'Action = "status.copy"' in CONFIG,
    "Status & Server tab exposes refresh and copy actions",
)
require(
    'Kind = "statusValue"' in CONFIG
    and "statusValues = statusValues" in STATE
    and "function State:SetStatusValues(values)" in STATE
    and "snapshot.statusValues[entry.Key]" in UI,
    "read-only status rows update from isolated state snapshots",
)
require(
    all(
        f'Key = "{key}"' in CONFIG
        for key in (
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
    "active quest details reuse validated target matching and expose supported progress",
)
require(
    all(
        f'Key = "{key}"' in CONFIG
        for key in (
            "serverUptime",
            "legendaryItemTimer",
            "moon",
            "raidTimer",
            "prehistoricTimer",
            "mirageIsland",
            "prehistoricIsland",
            "frozenDimension",
            "tikiEyes",
        )
    )
    and "function readWorldEventValues(context)" in FEATURE
    and 'readGuiTimer(compatibility, "RaidTimer")' in FEATURE
    and 'readGuiTimer(compatibility, "PrehistoricRaidTimer")' in FEATURE
    and 'location:GetAttribute("TimeIn")' in FEATURE
    and '" (estimate)"' in FEATURE,
    "world-event status uses local timers and labels the legendary-item window as an estimate",
)
require(
    "function StatusFeature:_ReadValues()" in FEATURE
    and "function StatusFeature:_BuildReport(values)" in FEATURE
    and 'values.fullJobId' in FEATURE
    and 'context.State:SetStatusValues(self:_ReadValues())' in FEATURE
    and "InvokeServer" not in FEATURE
    and "CommF_" not in FEATURE
    and "StatusFeature" in MANAGER,
    "status report gathers local player and server data without invoking remotes",
)
require(
    "snapshot.selectedTab == \"StatusServer\"" in FEATURE
    and "task.wait(1)" in FEATURE
    and "self._generation = (self._generation or 0) + 1" in FEATURE,
    "event timers refresh only while the Status tab is open and stop on cleanup",
)
require(
    "StatusValueEntries" in UI
    and 'control.Kind == "statusValue"' in UI
    and "Name = self:_ControlNodeName(control)" in UI,
    "status rows use the existing hub card style and refresh lifecycle",
)
