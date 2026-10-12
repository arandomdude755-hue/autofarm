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
    and "_IndexEnemyModel(instance)" in enemy_index
    and "_UnindexEnemyModel(instance)" in enemy_index
    and "GetDescendants()" in enemy_index,
    "enemy model discovery must seed once and maintain its name indexes from hierarchy events",
)
require(
    "DescendantAdded:Connect" in spawn_index
    and "DescendantRemoving:Connect" in spawn_index
    and "_IndexSpawnMarker(instance)" in spawn_index
    and "_UnindexSpawnMarker(instance)" in spawn_index
    and "GetDescendants()" in spawn_index,
    "spawn marker discovery must seed once and maintain its name indexes from hierarchy events",
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
    and "EnemyModelsByName[normalizedName]" in find_nearest
    and "for enemy in pairs(enemyModels)" not in find_nearest
    and "_GetEnemyModelIndex()" in find_in_range
    and "GetDescendants()" not in find_in_range,
    "quest-target searches must use normalized-name buckets instead of scanning every loaded model",
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
clear_target = function_body(
    MAIN,
    "function MainFarm:_ClearTarget(",
    "\nfunction MainFarm:_ResetSpawnSearch(",
)
require(
    prepare_target.index("self.PreparedTargets[model]") < prepare_target.index("model:GetDescendants()")
    and "table.clear(self.PreparedTargets)" in restore_collision,
    "target collision preparation must not rescan the same model every farm step",
)
require(
    "CollisionPartsByTarget" in prepare_target
    and "RestoreTargetCollision(self.Target)" in clear_target
    and "humanoid.Health <= 0" in restore_collision
    and "if shouldRestore then" in restore_collision
    and "part.CanCollide ~= originalCanCollide" in restore_collision
    and "self.CollisionPartsByTarget[target] = nil" in restore_collision
    and restore_collision.index("if shouldRestore then")
    < restore_collision.index("for part, originalCanCollide in pairs(targetParts)")
    < restore_collision.index("self.CollisionPartsByTarget[target] = nil"),
    "clearing a defeated target must discard its collision records without iterating or rewriting corpse parts",
)

find_spawn = function_body(ENEMY, "function EnemyService:FindSpawn", "\nfunction EnemyService:IsSpawnAvailable")
refresh_hidden_spawns = function_body(
    ENEMY,
    "function EnemyService:_RefreshHiddenSpawnCache()",
    "\nfunction EnemyService:_PruneIgnoredSpawns(",
)
require(
    "HIDDEN_SPAWN_REFRESH_INTERVAL = 5" in ENEMY
    and "HIDDEN_SPAWN_RETRY_INTERVAL = 10" in ENEMY
    and find_spawn.index("if not hiddenCache and not nearest then")
    < find_spawn.index("self:_RefreshHiddenSpawnCache()")
    and "hiddenCache.ByName[normalizedName]" in find_spawn,
    "expensive hidden-instance enumeration must be fallback-only, infrequent, and name-indexed",
)
require(
    "task.defer(" in refresh_hidden_spawns
    and "HIDDEN_SPAWN_SCAN_CHUNK_SIZE" in refresh_hidden_spawns
    and "task.wait()" in refresh_hidden_spawns
    and "cache.Loading = false" in refresh_hidden_spawns
    and "not hiddenCache.Loading" in find_spawn
    and "HiddenDiscoveryLoading" in find_spawn
    and "Checking hidden spawn markers in the background" in MAIN,
    "unparented-instance fallback must be asynchronous and chunked, never block target acquisition",
)
require(
    "SpawnMarkersByName[normalizedName]" in find_spawn
    and "for spawnPart in pairs(spawnMarkers)" not in find_spawn,
    "normal spawn lookup must inspect only marker buckets matching the active quest target",
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
clear_tracking = function_body(ENEMY, "function EnemyService:ClearTracking()", "\nfunction EnemyService:PrepareTarget")
require(
    "self.EnemyNameConnections" in clear_tracking
    and "EnemyModelsByName = {}" in clear_tracking
    and "SpawnMarkersByName = {}" in clear_tracking,
    "name-index connections and buckets must be released when Main Farm stops",
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
print("PASS: event-maintained name indexes and one-time collision preparation")
print("PASS: hidden-instance fallback is lazy, indexed, and rate-limited")
print("PASS: combat hit scans are skipped during attack cooldowns")
print("PASS: player collision suppression uses character/part events instead of a Heartbeat full scan")
