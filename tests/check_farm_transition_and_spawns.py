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
        and "spawnPart.Position - origin" in ENEMY,
        "multiple matching spawn markers must be selected by proximity")
require('"EnemySpawns"' in ENEMY and "getnilinstances" not in ENEMY,
        "spawn lookup must stay within replicated Workspace data")
require("Speed = 190" in FARM and "route and 190" in MOVEMENT,
        "movement speed must remain 190")

print("PASS: request confirmation is state-based and a timed-out quest is not retried automatically")
print("PASS: normal quest transitions preserve a held movement session; explicit cleanup remains")
print("PASS: NPC/spawn search is throttled, spawn-load bounded, nearest-first, and retryable")
