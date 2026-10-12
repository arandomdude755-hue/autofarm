from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
MAIN = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
ENEMY = (HUB / "Features/Farm/EnemyService.lua").read_text(encoding="utf-8")
COMBAT = (HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")
MOVEMENT = (HUB / "Features/Farm/MovementService.lua").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


run_loop = function_body(MAIN, "function MainFarm:_Run(session)", "\nfunction MainFarm:Start()")
require(
    "FARM_STEP_INTERVAL = 0.1" in MAIN
    and "task.wait(FARM_STEP_INTERVAL)" in run_loop
    and "task.wait()" not in run_loop,
    "farm work must yield at a bounded 10 Hz cadence instead of running every rendered frame",
)
require(
    "NPC_SCAN_INTERVAL = 0.75" in MAIN and "SPAWN_SCAN_INTERVAL = 1" in MAIN,
    "full enemy and spawn searches must not repeat multiple times per second",
)

enemy_index = function_body(
    ENEMY,
    "function EnemyService:_GetEnemyModelIndex()",
    "\nfunction EnemyService:_GetSpawnMarkerIndex()",
)
spawn_index = function_body(
    ENEMY,
    "function EnemyService:_GetSpawnMarkerIndex()",
    "\nfunction EnemyService:_RefreshHiddenSpawnCache()",
)
require(
    "DescendantAdded:Connect" in enemy_index
    and "DescendantRemoving:Connect" in enemy_index
    and "GetDescendants()" in enemy_index,
    "enemy model discovery must seed once and maintain its index from hierarchy events",
)
require(
    "DescendantAdded:Connect" in spawn_index
    and "DescendantRemoving:Connect" in spawn_index
    and "GetDescendants()" in spawn_index,
    "spawn marker discovery must seed once and maintain its index from hierarchy events",
)

find_nearest = function_body(ENEMY, "function EnemyService:FindNearest(", "\nfunction EnemyService:FindNearestInRange")
find_in_range = function_body(
    ENEMY,
    "function EnemyService:FindNearestInRange",
    "\nfunction EnemyService:FindSpawn",
)
require(
    "_GetEnemyModelIndex()" in find_nearest
    and "GetDescendants()" not in find_nearest
    and "_GetEnemyModelIndex()" in find_in_range
    and "GetDescendants()" not in find_in_range,
    "repeated target searches must reuse the event-maintained enemy index",
)

prepare_target = function_body(
    ENEMY,
    "function EnemyService:PrepareTarget",
    "\nfunction EnemyService:RestoreTargetCollision",
)
restore_collision = function_body(
    ENEMY,
    "function EnemyService:RestoreTargetCollision",
    "\nreturn EnemyService",
)
require(
    prepare_target.index("self.PreparedTargets[model]") < prepare_target.index("model:GetDescendants()")
    and "table.clear(self.PreparedTargets)" in restore_collision,
    "target collision preparation must not rescan the same model every farm step",
)

find_spawn = function_body(ENEMY, "function EnemyService:FindSpawn", "\nfunction EnemyService:IsSpawnAvailable")
require(
    "HIDDEN_SPAWN_REFRESH_INTERVAL = 5" in ENEMY
    and "HIDDEN_SPAWN_RETRY_INTERVAL = 10" in ENEMY
    and find_spawn.index("if not hiddenCache and not nearest then")
    < find_spawn.index("self:_RefreshHiddenSpawnCache()")
    and "hiddenCache.ByName[normalizedName]" in find_spawn,
    "expensive hidden-instance enumeration must be fallback-only, infrequent, and name-indexed",
)

attack = function_body(
    COMBAT,
    "function CombatService:AttackM1",
    "\nfunction CombatService:Cancel",
)
require(
    attack.index("combatUtil:CanAttack(character, weaponType)")
    < attack.index("self:_GetAttackCandidates("),
    "combat timing must reject attacks before allocating and scanning hit candidates",
)
require(
    "function EnemyService:ClearTracking()" in ENEMY
    and "self.EnemyService:ClearTracking()" in MAIN,
    "event-based indexes must disconnect when Main Farm stops",
)

farm_collision = function_body(
    MOVEMENT,
    "function MovementService:_RestoreFarmCollision()",
    "\nfunction MovementService:_Finish(",
)
require(
    "Heartbeat:Connect" not in farm_collision
    and "character:GetDescendants()" in farm_collision
    and "character.DescendantAdded:Connect" in farm_collision
    and 'GetPropertyChangedSignal("CanCollide")' in farm_collision
    and "player.CharacterAdded:Connect" in farm_collision,
    "farm collision work must scan once per character and use part/respawn events instead of per-frame rescans",
)

print("PASS: bounded farm cadence and throttled discovery intervals")
print("PASS: event-maintained enemy/spawn indexes and one-time collision preparation")
print("PASS: hidden-instance fallback is lazy, indexed, and rate-limited")
print("PASS: combat hit scans are skipped during attack cooldowns")
print("PASS: player collision suppression uses character/part events instead of a Heartbeat full scan")
