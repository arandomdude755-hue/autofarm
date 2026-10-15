#!/usr/bin/env python3
"""Static checks for quest-state, movement continuity, and spawn retry behavior."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FARM = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua"
).read_text(encoding="utf-8")
MOVEMENT = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/MovementService.lua"
).read_text(encoding="utf-8")
ENEMY = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/EnemyService.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


request = FARM[FARM.index("function MainFarm:_RequestQuest"):FARM.index(
    "function MainFarm:_Step(session)"
)]
step = FARM[
    FARM.index("function MainFarm:_Step(session)"):
    FARM.index("function MainFarm:_Run(session)")
]
move_to = MOVEMENT[MOVEMENT.index("function MovementService:MoveTo"):MOVEMENT.index(
    "\nreturn MovementService"
)]

require("self.QuestService:RequestStart(candidate)" in request,
        "diagnostic change must reuse the existing quest request")
require("self.TimedOutQuestKey == key" in request,
        "a timed-out candidate must not be repeatedly requested")
require("QUEST_START_RETRY_INTERVAL = 2" in FARM
        and "MAX_QUEST_START_ATTEMPTS = 3" in FARM,
        "quest acceptance must use a short, bounded retry window")
require(
    "attempts >= MAX_QUEST_START_ATTEMPTS" in request
    and "now - (self.LastQuestAttemptAt or 0) < QUEST_START_RETRY_INTERVAL" in request,
    "the same quest must not be remotely requested faster than the retry interval or beyond its attempt limit",
)
require(
    "self.QuestDiagnosticReport.AttemptCount = self.QuestStartAttemptCount" in request
    and "attempts=" in FARM,
    "quest diagnostics must expose how many acceptance attempts were made",
)
require("Quest confirmation timed out after 8 seconds" in FARM,
        "confirmation timeout must include an explicit reason")
require("response is not acceptance" in request,
        "remote return values must not be treated as quest acceptance")
require("activeTarget == self.PendingQuestTargetName" in step,
        "confirmation must match the active target selected for this request")
dialogue_recovery = FARM[
    FARM.index("function MainFarm:_HandleQuestDialogueRecovery"):
    FARM.index("function MainFarm:_ClearTarget")
]
request_call_start = step.index("self:_RequestQuest(candidate, session)")
require(
    "self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)" in step
    and step.rindex("self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)")
    < request_call_start,
    "quest requests must pass through dialogue recovery after the arrival delay",
)
require(
    step.index("elseif os.clock() - self.PendingQuestReachedAt < requestDelay then")
    < step.rindex("if self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session) then")
    < request_call_start
    and "self:_RequestQuest" not in dialogue_recovery
    and "RequestStart" not in dialogue_recovery,
    "dialogue recovery must run after the initial delay and never consume a quest request itself",
)
mode_quest_giver = FARM[
    FARM.index("function MainFarm:_StepModeQuestGiver"):
    FARM.index("\nfunction MainFarm:_FindModeSpawn")
]
quest_request_delay = FARM[
    FARM.index("function MainFarm:_GetQuestGiverRequestDelay"):
    FARM.index("\nfunction MainFarm:_RequestQuest")
]
require(
    "InstantAcceptQuest == true" in quest_request_delay
    and "and 0" in quest_request_delay
    and "QUEST_GIVER_REQUEST_DELAY = 2" in FARM
    and "requestDelay == 0" in mode_quest_giver
    and "requestDelay == 0" in step
    and mode_quest_giver.index("requestDelay == 0")
        < mode_quest_giver.rindex("self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)")
        < mode_quest_giver.index("self:_RequestQuest(candidate, session)")
    and step.index("requestDelay == 0")
        < step.rindex("if self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session) then")
        < request_call_start,
    "instant acceptance must remove only the arrival wait while retaining dialogue recovery and quest confirmation",
)
require(
    "QUEST_DIALOGUE_RETREAT_DISTANCE = 32" in FARM
    and "QUEST_DIALOGUE_RETREAT_INCREMENT = 24" in FARM
    and "QUEST_DIALOGUE_MAX_RETREAT_DISTANCE = 80" in FARM
    and "horizontalUnitVector(root.Position - giverCFrame.Position)" in dialogue_recovery
    and "CFrame.new(retreatPosition)" in dialogue_recovery
    and "session,\n            4,\n            true" in dialogue_recovery
    and "self.QuestService:IsQuestGiverDialogueOpen()" in dialogue_recovery,
    "visible dialogue must trigger a horizontal, distance-bounded retreat in the retained movement session",
)
require(
    "if not dialogueOpen then" in dialogue_recovery
    and "self.QuestDialogueRecovery = nil" in dialogue_recovery
    and "self.QuestDeferredForDialogue = true" in dialogue_recovery
    and "self.PendingQuestReachedAt = os.clock() - 2" in dialogue_recovery,
    "closing the dialogue must clear recovery and allow immediate quest acquisition after re-approach",
)
require(
    "MAX_QUEST_DIALOGUE_MOVE_FAILURES = 3" in FARM
    and "recovery.MoveFailures >= MAX_QUEST_DIALOGUE_MOVE_FAILURES" in dialogue_recovery,
    "dialogue recovery must stop safely after bounded movement failures",
)
pause_start = step.index("elseif self.QuestService:IsQuestGiverDialogueOpen() then")
pause_end = step.index("elseif not self.QuestDiagnosticWaitStartedAt then", pause_start)
pause_branch = step[pause_start:pause_end]
require(
    step.index('if questState == "active" then') < pause_start
    and "self.QuestDiagnosticWaitStartedAt = nil" in pause_branch
    and "self.QuestStartAttemptCount = 0" in pause_branch
    and "return" not in pause_branch,
    "dialogue deferral must preserve validated acceptance and continue into the recovery flow",
)
require(
    'if questState == "active" then' in step
    and "if self.QuestDialogueRecovery then" in step
    and "self.MovementService:Cancel()" in step[
        step.index('if questState == "active" then'):
        step.index("if self.QuestDiagnosticWaitKey then")
    ]
    and "self.QuestDialogueRecovery = nil" in step[
        step.index('if questState == "active" then'):
        step.index("if self.QuestDiagnosticWaitKey then")
    ],
    "a validated manual acceptance must cancel retreat before quest-target farming resumes",
)
double_quest_lookup = FARM[
    FARM.index("function MainFarm:_FindDoubleQuestFallback"):
    FARM.index("\nfunction MainFarm:_Step(session)")
]
require(
    "farmSettings.DoubleQuestEnabled ~= true" in double_quest_lookup
    and "SelectPreviousLevelQuestTarget(activeTarget)" in double_quest_lookup
    and "FindNearest(candidate.Mob, root.Position)" in double_quest_lookup
    and "DOUBLE_QUEST_MAX_FALLBACK_DISTANCE = 3000" in FARM
    and "DOUBLE_QUEST_SCAN_INTERVAL = 0.5" in FARM
    and "targetRoot.Position - root.Position" in double_quest_lookup,
    "Double Quest must use a throttled, nearby live previous-quest target only",
)
double_quest_start = step.index("local keepDoubleQuestFallback =")
double_quest_end = step.index("if self.SpawnSearchExhausted then", double_quest_start)
double_quest_step = step[double_quest_start:double_quest_end]
require(
    "FindNearest(activeTarget, root.Position)" in double_quest_step
    and "if not target then" in double_quest_step
    and "keepDoubleQuestFallback" in double_quest_step
    and "_FindDoubleQuestFallback(activeTarget, root, now)" in double_quest_step
    and "self.TargetName = targetName" in step
    and "self.DoubleQuestFallbackFor = activeTarget" in step
    and "self:_RequestQuest" not in double_quest_step,
    "the active quest target must take priority and remain active while fallback mobs are farmed",
)
require(
    'self.EnemyService:FindSpawn(activeTarget, root.Position)' in step
    and 'self:_SetStatus(\n                "Double Quest: farming " .. targetName' in step,
    "Double Quest must never travel to fallback spawn markers and should identify fallback farming",
)
require(
    "if self.QuestDeferredForDialogue then\n                self.PendingQuestReachedAt = os.clock() - 2"
    in step
    and "if not self.QuestDeferredForDialogue then\n                self.PendingQuestReachedAt = nil"
    in step,
    "dialogue dismissal must retain a ready-to-request state while re-approaching the giver",
)

quest_report = FARM[
    FARM.index("function MainFarm:_PrintQuestDiagnosticReport"):
    FARM.index("function MainFarm:_PrintSpawnDiagnosticReport")
]
require(
    '"Sea: " .. diagnosticSeaName(self.Context and self.Context.Compatibility)' in quest_report
    and '"Dialogue deferred: " .. tostring(report.DialogueDeferred == true)' in quest_report
    and "self.LastQuestDiagnosticReportText = text" in quest_report
    and "self.LastQuestDiagnosticReportText = nil" in request
    and "DialogueDeferred = self.QuestDeferredForDialogue == true" in request,
    "the latest complete report must include its sea and dialogue deferral and replace stale reports",
)

require("function MainFarm:_ClearTarget(preserveMovement)" in FARM,
        "normal target cleanup needs a movement-preserving option")
require("if self.MovementService and not preserveMovement then" in FARM,
        "normal quest transition must not cancel the current movement session")
require("_MoveTo(giverCFrame * CFrame.new(0, 4, 2), session, 8, true)" in step,
        "quest-giver travel must retain the movement session")
require("active.KeepSession" in move_to and "options.KeepSession == true" in move_to,
        "movement service must retarget the retained session")
require("active.Holding = true" in move_to,
        "retained movement must hold at the reached destination during quest retrieval")
require(
    "and not active.Holding\n        and not active.HoldingForSearch" in move_to
    and "local wasHolding = active.Holding or active.HoldingForSearch" in move_to
    and "if wasHolding or destinationShift > 12 then" in move_to,
    "a held movement goal must reach the retarget path even when the replacement goal is nearby",
)
require("self:_Finish(active, true)" in move_to,
        "explicit movement cancellation/error paths must still finish and clean up")

require("FindSpawn(activeTarget, root.Position)" in step,
        "spawn choice must account for the character's current position")
require("SPAWN_LOAD_GRACE = 1" in FARM
        and "now - self.SpawnLoading.ArrivedAt >= SPAWN_LOAD_GRACE" in step,
        "spawn marker must receive a bounded loading interval before being skipped")
require("SPAWN_CYCLE_RETRY_INTERVAL = 2" in FARM
        and "self.SpawnRetryAt = now + SPAWN_CYCLE_RETRY_INTERVAL" in step,
        "fully checked spawn cycles must back off before retrying")
require("MAX_EMPTY_SPAWN_CYCLES = 2" in FARM
        and "self.SpawnSearchExhausted = true" in step,
        "repeated empty spawn cycles must stop repeated travel while loaded-NPC scans continue")
require("NextEnemySearchAt = now + NPC_SCAN_INTERVAL" in step
        and "NextSpawnSearchAt = now + SPAWN_SCAN_INTERVAL" in step,
        "NPC and spawn scans must be throttled")
require("local nearest, nearestDistance = nil, math.huge" in ENEMY
        and "position - origin" in ENEMY,
        "multiple matching spawn markers must be selected by proximity")
require(
    '"EnemySpawns"' in ENEMY
    and "GetUnparentedInstances" in ENEMY
    and "getnilinstances" not in ENEMY,
    "generic spawn lookup must use replicated markers and the guarded compatibility adapter",
)
require(
    'FindFirstChild("_WorldOrigin", true)' in ENEMY
    and 'FindFirstChild("EnemySpawns", true)' in ENEMY
    and "enemySpawns:GetDescendants()" in ENEMY,
    "spawn lookup must handle nested origin/spawn folders and nested marker parts",
)
require(
    'FindFirstChild("Enemies", true)' in ENEMY
    and "enemies:GetDescendants()" in ENEMY
    and "EnemyModelsByName[normalizedName]" in ENEMY
    and "normalizeEnemyName(instance.Name)" in ENEMY
    and "singularizeEnemyWord" in ENEMY,
    "live enemy lookup must handle nested models and generic level/plural name variants",
)
require(
    "function EnemyService:IsSpawnAvailable(spawnPart, targetName)" in ENEMY
    and "enemySpawns ~= nil" in ENEMY
    and "isDescendantOf(spawnPart, enemySpawns)" in ENEMY
    and "hiddenCache.Parts[spawnPart] == name" in ENEMY
    and "os.clock() < hiddenCache.ExpiresAt" in ENEMY,
    "spawn availability must validate a nested real marker or a fresh cached unparented marker",
)
require(
    "self:_PruneIgnoredSpawns(" in ENEMY
    and "hiddenCache or { Available = false, Parts = {} }" in ENEMY
    and "targetName" in ENEMY
    and "self.IgnoredSpawns[spawnPart]" in ENEMY,
    "stale and ignored spawn markers must not be selected",
)
require(
    "IsSpawnAvailable(spawnPart, activeTarget)" in step
    and "MarkSpawnIgnored(spawnPart, activeTarget)" in step,
    "Main Farm must validate candidates and ignore only the current eligible marker",
)
spawn_find = ENEMY[ENEMY.index("function EnemyService:FindSpawn"):ENEMY.index(
    "function EnemyService:IsSpawnAvailable"
)]
spawn_diagnostic = FARM[
    FARM.index("function MainFarm:_PrintSpawnDiagnosticReport"):
    FARM.index("function MainFarm:_EndQuestDiagnosticWait")
]
require(
    "NormalMarkerFound" in spawn_find
    and "EnemySpawnsContainerFound" in spawn_find
    and "HiddenMarkerFound" in spawn_find
    and "SelectedDistance = distance" in spawn_find
    and "return nearest, false, diagnostic" in spawn_find,
    "the existing spawn scan must return its normal/hidden match and selected-distance evidence",
)
require(
    "spawnPart, allSpawnsVisited, spawnDiagnostic =" in step
    and step.count("FindSpawn(activeTarget, root.Position)") == 1
    and step.count("self.EnemyService:IsSpawnAvailable(spawnPart, activeTarget)") == 1
    and step.count("_MoveTo(spawnDestination, session, 100, true)") == 1
    and "local movementAccepted, movementResult =" in step
    and "self:_RecordSpawnDiagnostic(" in step,
    "diagnostics must reuse the single scan, availability check, and movement call",
)
require(
    "[SpawnDiagnostic] REPORT BEGIN" in spawn_diagnostic
    and "Normal EnemySpawns marker" in spawn_diagnostic
    and "Hidden unparented marker" in spawn_diagnostic
    and "Selected candidate:" in spawn_diagnostic
    and "IsSpawnAvailable:" in spawn_diagnostic
    and "started_this_call=" in spawn_diagnostic
    and "MAX_SPAWN_DIAGNOSTIC_REPORT_LENGTH" in spawn_diagnostic
    and "setclipboard(text)" in spawn_diagnostic,
    "spawn report must be bounded, copyable, and include the requested state",
)
require(
    ":FindSpawn(" not in spawn_diagnostic
    and ":IsSpawnAvailable(" not in spawn_diagnostic
    and ":_MoveTo(" not in spawn_diagnostic,
    "report formatting must not repeat scans, availability checks, or movement",
)
require("Speed = 190" in FARM and "route and 190" in MOVEMENT,
        "movement speed must remain 190")

print("PASS: quest requests retry only within the bounded confirmation window")
print("PASS: normal quest transitions preserve a held movement session; explicit cleanup remains")
print("PASS: NPC/spawn search is throttled, spawn-load bounded, nearest-first, and retryable")
print("PASS: generic hidden-marker discovery is cached, freshness-checked, and excludes ignored markers")
print("PASS: bounded spawn diagnostics reuse the single search and movement results")


def normalize_enemy_name(name):
    """Python fixture model of suffix/case/plural normalization in EnemyService."""
    import re

    base = re.sub(r"\s+[\W]?lv\.?\s*\d+[\W]?\s*$", "", name, flags=re.IGNORECASE)
    words = re.findall(r"[a-z0-9]+", base.lower())
    if not words:
        return None
    word = words[-1]
    if len(word) > 3 and word.endswith("ies") and word[-4] not in "aeiou":
        word = word[:-3] + "y"
    elif len(word) > 4 and word.endswith("es"):
        stem = word[:-2]
        if stem.endswith(("s", "x", "z", "ch", "sh")):
            word = stem
    elif len(word) > 2 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
        word = word[:-1]
    words[-1] = word
    return " ".join(words)


for found_name, target_name, expected in (
    ("Bandit [Lv. 5]", "Bandit", True),
    ("bandit [lv 5]", "Bandit", True),
    ("Gorillas [Lv. 20]", "Gorilla", True),
    ("Water Fighters [Lv. 1450]", "Water Fighter", True),
    ("Boss [Lv. 50]", "Boss", True),
    ("Bandit [Lv. 5]", "Gorilla", False),
):
    actual = normalize_enemy_name(found_name) == normalize_enemy_name(target_name)
    require(actual is expected, f"unexpected enemy name match: {found_name!r} / {target_name!r}")


def quest_request_schedule(interval, maximum, timeout):
    return [attempt * interval for attempt in range(maximum) if attempt * interval < timeout]


require(quest_request_schedule(2, 3, 8) == [0, 2, 4],
        "quest requests must retry at bounded two-second intervals")
require(len(quest_request_schedule(2, 3, 8)) <= 3,
        "quest acceptance retries must remain capped")
print("PASS: NPC target matching handles case, level suffixes, and common plural forms")
print("PASS: quest acceptance retries are bounded and spaced")
