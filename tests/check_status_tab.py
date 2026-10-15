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
    and "seaEventSignal" not in CONFIG
    and "raidTimer" not in CONFIG
    and "prehistoricTimer" not in CONFIG
    and '"Health"' not in CONFIG
    and '"Character"' not in CONFIG
    and 'Label = "Chalice / Fist status"' in CONFIG
    and 'Key = "moon", Label = "Moon phase"' in CONFIG
    and "function readWorldEventValues(context, statusFeature)" in FEATURE
    and 'location:GetAttribute("TimeIn")' in FEATURE
    and "workspace:GetServerTimeNow()" in FEATURE
    and "tick() - 25200" in FEATURE
    and "local function readLegendaryItemStatus(context, workspace, elapsed)" in FEATURE
    and '"Next: "' in FEATURE
    and '" .. shortName .. " held"' in FEATURE
    and '"; summon active"' in FEATURE
    and '"No held Chalice/Fist or active summon observed; next four-hour boundary in "' not in FEATURE
    and "Fist of Darkness" in FEATURE
    and "acquisition source=unknown" in FEATURE
    and "appendClockDiagnostics(lines, workspace)" in FEATURE
    and "Server-clock next 4-hour boundary" in FEATURE
    and "BNN-clock next 4-hour boundary" in FEATURE
    and "appendLegendaryItemDiagnostics(lines, context, workspace)" in FEATURE
    and "appendIslandDiagnostics(lines, context, remoteEvents)" in FEATURE
    and "appendUnparentedIslandDiagnostics(lines, compatibility)" in FEATURE
    and "appendNamedDescendantMatches(lines, map, \"Workspace.Map\")" in FEATURE
    and "World-origin location names (up to " in FEATURE
    and "collectHeldLegendaryItems(playersService, 1)" in FEATURE
    and '"Mirage Island", MapName = "MysticIsland"' in FEATURE
    and '"Prehistoric Island", MapName = "PrehistoricIsland"' in FEATURE
    and '"Frozen Dimension", MapName = "Frozen Dimension"' in FEATURE
    and '"Tiki Outpost", MapName = "TikiOutpost"' in FEATURE
    and "local scanLimit = math.min(#instances, 5000)" in FEATURE
    and 'findChild(locations, "Frozen Dimension")' in FEATURE
    and 'getIfCurrentRealmHasTagAsync' in FEATURE
    and '"HasMirageIsland"' in FEATURE
    and 'local function readEventPresence(marker)' in FEATURE
    and 'return marker and "Spawned" or "Not spawned"' in FEATURE
    and 'findChild(locations, "Prehistoric Island")' not in FEATURE
    and 'and readEventPresence(mirage)' in FEATURE
    and 'and readEventPresence(prehistoric)' in FEATURE
    and 'and readEventPresence(frozenDimension)' in FEATURE
    and 'readEventPresence(mirage,' not in FEATURE
    and "local storedElite = findAliveElite(replicatedStorage)" in FEATURE
    and 'return "Spawned: " .. storedElite.Name' in FEATURE
    and FEATURE.split("local function readEliteHunterStatus", 1)[1].split(
        "local function readEventPresence", 1
    )[0].find("findAliveElite(replicatedStorage)")
    < FEATURE.split("local function readEliteHunterStatus", 1)[1].split(
        "local function readEventPresence", 1
    )[0].find('findChild(workspace, "Enemies")')
    and '"Not spawned (template loaded: "' not in FEATURE
    and 'formatCompactDuration(untilNextCycle)' in FEATURE
    and '"; summon active"' in FEATURE
    and '" .. shortName .. " held"' in FEATURE
    and '"Next: "' in FEATURE
    and '" · Calculating"' in FEATURE
    and 'Tiki Outpost location entry is a travel-location marker; it does not prove eye-event state.' in FEATURE
    and "function updateMoonClockRate(statusFeature, clockTime)" in FEATURE
    and "elapsed >= 8" in FEATURE
    and "local function moonForecast(phaseText, clockTime, phaseNumber)" in FEATURE
    and "Phase %d (%d nights until Full Moon)" in FEATURE
    and 'return "Full Moon ends in", 5 - clockTime' in FEATURE
    and 'return "Next Full Moon in", targetClock - clockTime' in FEATURE
    and 'local function formatMoonEstimate(realSeconds)' in FEATURE
    and 'return string.format("~%dh %02dm", hours, remainingMinutes)' in FEATURE
    and 'return string.format("~%dd %02dh", math.floor(hours / 24), hours % 24)' in FEATURE
    and 'return string.format("~%dm", minutes)' in FEATURE
    and 'local displayPhase = phaseText:match("^(Phase %d+)") or phaseText' in FEATURE
    and '" real time (estimate)"' not in FEATURE
    and '"game clock "' not in FEATURE
    and '" | no timing estimate"' not in FEATURE
    and "ELITE_TARGET_NAMES" in FEATURE
    and '"Not spawned"' in FEATURE
    and '"Not spawned (template loaded: "' not in FEATURE
    and "function readTikiEyes(map)" in FEATURE
    and 'return "Not loaded"' in FEATURE
    and '" not visible"' in FEATURE
    and 'Eye" .. tostring(index)' in FEATURE
    and "Third Sea only" in FEATURE
    and 'gsub("<[^>]+>", "")' in FEATURE,
    "Event Status follows BNN's event sources and shows compact moon and island states",
)
require(
    "function StatusFeature:_ReadValues()" in FEATURE
    and "function StatusFeature:_BuildReport(values)" in FEATURE
    and FEATURE.split("function StatusFeature:_ReadValues()", 1)[1].split(
        "function StatusFeature:_BuildReport(values)", 1
    )[0].find("GetUnparentedInstances") == -1
    and 'values.fullJobId' in FEATURE
    and "===== [StatusReport] REPORT END =====" in FEATURE
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
    and 'local titleWidth = control.Key == "moon" and 0.36 or 0.45' in UI
    and "local valueWidth = 1 - titleWidth" in UI
    and "Name = self:_ControlNodeName(control)" in UI,
    "status rows use the existing hub card style and refresh lifecycle",
)
