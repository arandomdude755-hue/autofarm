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
    and 'Action = "stack.eliteHunter.enabled"' in CONFIG
    and 'Action = "stack.fruit.enabled"' in CONFIG
    and 'Action = "stack.berry.enabled"' in CONFIG
    and "SpecialHop" not in CONFIG,
    "Stack Farming must expose Cake Prince, Elite Hunter, fruit and berries without hop controls",
)
require(
    "AutoAttackCakePrince = false" in CONFIG
    and "AutoEliteHunter = false" in CONFIG
    and "TeleportToFruit = false" in CONFIG
    and "AutoCollectBerries = false" in CONFIG,
    "Stack Farming tasks must default to off",
)

require(
    'instance.Name == "Cake Prince"' in QUEUE
    and 'string.lower(instance.Name), "fruit"' in QUEUE,
    "the event queue must detect Cake Prince and fruit candidates",
)
require(
    "Deandre = true" in QUEUE
    and "Urban = true" in QUEUE
    and "Diablo = true" in QUEUE
    and "instance.Parent ~= self.EnemiesFolder" in QUEUE
    and 'folder.ChildAdded:Connect(function(instance)' in QUEUE
    and 'self:_ObserveEliteHunter(instance)' in QUEUE,
    "Elite Hunter tasks should queue only live world targets from Workspace.Enemies",
)
require(
    '"BerryBush"' in QUEUE
    and 'GetInstanceAddedSignal("BerryBush")' in QUEUE
    and 'GetInstanceRemovedSignal("BerryBush")' in QUEUE
    and "AttributeChanged:Connect" in QUEUE
    and "function StackTaskQueue:GetBerryPickup" in QUEUE,
    "berry collection should detect tagged, active bushes from events and resolve their pickup target",
)
require(
    "workspaceService.ChildAdded:Connect" in QUEUE
    and "folder.ChildAdded:Connect" in QUEUE
    and "left.QueueSequence < right.QueueSequence" in QUEUE
    and "QueueSequence = spawnSequence" in QUEUE,
    "spawn discovery must be event-driven and preserve priority across task types",
)
require(
    "findFruitHandle(instance)" in QUEUE
    and "instance.DescendantAdded:Connect(checkReady)" in QUEUE
    and "instance.Parent ~= self.Workspace" in QUEUE
    and "instance.Parent == self.Workspace" in QUEUE,
    "fruit tasks should queue as soon as a real handle is ready and only while the fruit is a world item",
)
require(
    "local function optimizeFruitRun" in QUEUE
    and "local fullMask = 2 ^ count - 1" in QUEUE
    and "local ordered = optimizeFruitRun(fruitRun, currentPosition, estimateTravelCost)"
    in QUEUE
    and "entry.QueueSequence = queueSlots[fruitIndex]" in QUEUE,
    "consecutive fruit pickups should use the shortest available route order",
)
require(
    "function MapGatewayService:EstimateTravelDistance" in (
        ROOT / "src/ReplicatedStorage/CustomHub/Features/MapGatewayService.lua"
    ).read_text(encoding="utf-8")
    and "function TeleportFeature:EstimateFarmTravelDistance" in (
        ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua"
    ).read_text(encoding="utf-8")
    and "queue:PopNext(root.Position, estimateTravelCost)" in MAIN_FARM,
    "fruit route optimization should estimate the shared gateway-aware travel cost",
)
require(
    "while self.Pending[index] and self.Pending[index].Kind == \"Fruit\" do" in QUEUE,
    "fruit optimization must not reorder across an earlier non-fruit stack task",
)
require(
    'self:_EngageModeTarget(target, true, root, session, "stack")' in MAIN_FARM
    and '"spawned fruit"' in MAIN_FARM,
    "stack jobs must use existing boss combat and shared farm travel",
)
elite_quest = MAIN_FARM.split("function MainFarm:_EnsureEliteHunterQuest", 1)[1].split(
    "\nfunction MainFarm:", 1
)[0]
require(
    'commF:InvokeServer("EliteHunter")' in elite_quest
    and 'commF:InvokeServer("AbandonQuest")' in elite_quest
    and "string.find(string.lower(questTitle)" in MAIN_FARM
    and 'self:_EngageModeTarget(target, true, root, session, "stack")' in MAIN_FARM
    and "only available in Third Sea" in MAIN_FARM
    and "or self.Enabled.EliteHunter == true" in QUEUE,
    "Elite Hunter must accept and confirm its matching quest, use shared combat, and stay Sea 3 only",
)
require(
    'prompt:InputHoldBegin()' in MAIN_FARM
    and 'prompt:InputHoldEnd()' in MAIN_FARM
    and 'self:_MoveTo(' in MAIN_FARM
    and '"berry"' in MAIN_FARM,
    "berry pickup must travel through the shared movement service and use the prompt",
)
require(
    'entry.Kind == "Fruit" and target.Parent ~= workspaceService' in MAIN_FARM
    and "if entry.HadHandle then" in MAIN_FARM,
    "fruit pickup/reparenting must finish the active task instead of waiting indefinitely",
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
require(
    "AutoCollectBerries == true" in TELEPORT
    and "AutoEliteHunter == true" in TELEPORT,
    "berry collection and Elite Hunter must prevent conflicting manual travel",
)

print("PASS: Main Farming and Stack Farming are separate nested pages")
print("PASS: stack jobs share one worker; fruit batches use gateway-aware route ordering")
print("PASS: standalone stack jobs and travel conflict handling are wired")
