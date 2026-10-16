from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEATURE_MANAGER = (
    ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua"
).read_text(encoding="utf-8")
COORDINATOR = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/TaskCoordinator.lua"
).read_text(encoding="utf-8")
MAIN_FARM = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua"
).read_text(encoding="utf-8")
TELEPORT = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua"
).read_text(encoding="utf-8")
SERVER_HOP = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/ServerHopService.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(
    "TaskCoordinator = taskCoordinator" in FEATURE_MANAGER
    and "self.Context.TaskCoordinator:Cleanup()" in FEATURE_MANAGER,
    "FeatureManager must provide one shared coordinator to features and clean it up",
)
require(
    'group == "StackFarm"' in COORDINATOR
    and 'current.Group == "MainFarm"' in COORDINATOR
    and 'current.Group == "Background"' in COORDINATOR
    and 'group == "Protected"' in COORDINATOR
    and "current.OnPreempt" in COORDINATOR,
    "Stack tasks can preempt Main Farming/manual Travel, and task travel can preempt manual Travel",
)
require(
    'coordinator:TryAcquire(\n                        "MainFarming"' in MAIN_FARM
    and 'coordinator:TryAcquire(\n            "StackFarming"' in MAIN_FARM
    and "coordinator:CanRunStack(self.ActiveStackLease)" in MAIN_FARM,
    "MainFarm and stack tasks must use coordinator leases and defer when blocked",
)
require(
    'coordinator:TryAcquire(\n        "Travel"' in TELEPORT
    and '"Background"' in TELEPORT
    and "function(preemptingGroup, preemptingLabel)" in TELEPORT
    and "coordinator:Release(request.CoordinatorLease)" in TELEPORT,
    "manual travel must hold a low-priority lease and stop cleanly when preempted",
)
require(
    'self.Coordinator:TryAcquire(\n            "StackFarming"' in SERVER_HOP
    and "function ServerHopService:OwnsLease(lease)" in SERVER_HOP
    and "self:_ReleaseCoordinatorLease()" in SERVER_HOP,
    "server hopping must coordinate active fetch/join work and release its lease",
)

print("Task coordinator checks passed")
