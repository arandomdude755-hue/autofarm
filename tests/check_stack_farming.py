from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text(encoding="utf-8")
MAIN_FARM = (ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua").read_text(
    encoding="utf-8"
)
QUEUE = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/StackTaskQueue.lua"
).read_text(encoding="utf-8")
TELEPORT = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(
    'Label = "Main Farming", Page = "Farm"'
    in CONFIG
    and 'Label = "Stack Farming", Page = "StackFarming"'
    in CONFIG,
    "Farm navigation must show Main Farming first and Stack Farming second",
)
require(
    'Title = "Main Farming"' in CONFIG and 'Title = "Stack Farming"' in CONFIG,
    "both Farm subsection pages must have clear page titles",
)
require(
    'Action = "stack.cakePrince.enabled"' in CONFIG
    and 'Action = "stack.fruit.enabled"' in CONFIG
    and "SpecialHop" not in CONFIG,
    "Stack Farming must expose Cake Prince and fruit only, with no hop controls",
)
require(
    "AutoAttackCakePrince = false" in CONFIG and "TeleportToFruit = false" in CONFIG,
    "Stack Farming tasks must default to off",
)

require(
    'instance.Name == "Cake Prince"' in QUEUE
    and 'string.lower(instance.Name), "fruit"' in QUEUE,
    "the event queue must detect Cake Prince and fruit candidates",
)
require(
    "workspaceService.ChildAdded:Connect" in QUEUE
    and "folder.ChildAdded:Connect" in QUEUE
    and "left.Sequence < right.Sequence" in QUEUE,
    "spawn discovery must be event-driven and dequeue tasks in observed spawn order",
)
require(
    'self:_EngageModeTarget(target, true, root, session, "stack")' in MAIN_FARM
    and '"spawned fruit"' in MAIN_FARM,
    "stack jobs must use existing boss combat and shared farm travel",
)
run_loop = MAIN_FARM.split("function MainFarm:_Run(session)", 1)[1].split(
    "function MainFarm:", 1
)[0]
require(
    run_loop.index("self:_StepStackTasks(session)")
    < run_loop.index("self:_Step(session)"),
    "Stack Farming must take priority in the single MainFarm worker loop",
)
require(
    "self.MainFarmEnabled = true" in MAIN_FARM
    and "self.MainFarmEnabled = false" in MAIN_FARM
    and "self:_StartWorker()" in MAIN_FARM,
    "stack jobs must be able to run on the shared worker while Main Farming is off",
)
require(
    "Turn off the active Stack Farming task before starting Travel."
    in TELEPORT,
    "manual travel must explain the Stack Farming conflict to the player",
)

print("PASS: Main Farming and Stack Farming are separate nested pages")
print("PASS: Cake Prince and fruit jobs are FIFO and share one farm worker")
print("PASS: standalone stack jobs and travel conflict handling are wired")
