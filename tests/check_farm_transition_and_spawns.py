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
    "function MainFarm:_Step"
)]
step = FARM[FARM.index("function MainFarm:_Step"):FARM.index("function MainFarm:_Run")]
move_to = MOVEMENT[MOVEMENT.index("function MovementService:MoveTo"):MOVEMENT.index(
    "\nreturn MovementService"
)]

require("self.QuestService:RequestStart(candidate)" in request,
        "diagnostic change must reuse the existing quest request")
require("self.TimedOutQuestKey == key" in request,
        "a timed-out candidate must not be repeatedly requested")
require("Quest confirmation timed out after 8 seconds" in FARM,
        "confirmation timeout must include an explicit reason")
require("response is not acceptance" in request,
        "remote return values must not be treated as quest acceptance")
require("activeTarget == self.PendingQuestTargetName" in step,
        "confirmation must match the active target selected for this request")

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
    "function EnemyService:IsSpawnAvailable(spawnPart, targetName)" in ENEMY
    and "enemySpawns ~= nil" in ENEMY
    and "hiddenCache.Parts[spawnPart] == name" in ENEMY
    and "os.clock() < hiddenCache.ExpiresAt" in ENEMY,
    "spawn availability must validate the real folder or a fresh cached unparented marker",
)
require(
    "self:_PruneIgnoredSpawns(enemySpawns, hiddenCache, targetName)" in ENEMY
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

print("PASS: request confirmation is state-based and a timed-out quest is not retried automatically")
print("PASS: normal quest transitions preserve a held movement session; explicit cleanup remains")
print("PASS: NPC/spawn search is throttled, spawn-load bounded, nearest-first, and retryable")
print("PASS: generic hidden-marker discovery is cached, freshness-checked, and excludes ignored markers")
print("PASS: bounded spawn diagnostics reuse the single search and movement results")
