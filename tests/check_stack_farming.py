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
HOP = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/ServerHopService.lua"
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
settings_page = CONFIG[
    CONFIG.index('Title = "Main settings"') : CONFIG.index('Title = "Farm settings"')
]
require(
    settings_page.index('Label = "Hub settings"')
    < settings_page.index('Label = "Team to auto-select"')
    < settings_page.index('Label = "Auto Execute"')
    < settings_page.index('Label = "Interface"'),
    "team selection and Auto Execute should be grouped under Hub settings",
)
require(
    'Action = "stack.cakePrince.enabled"' in CONFIG
    and 'Action = "stack.eliteHunter.enabled"' in CONFIG
    and 'Action = "stack.ripIndra.enabled"' in CONFIG
    and 'Action = "stack.soulReaper.enabled"' in CONFIG
    and 'Action = "stack.doughKing.enabled"' in CONFIG
    and 'Action = "stack.darkbeard.enabled"' in CONFIG
    and 'Action = "stack.saw.enabled"' in CONFIG
    and 'Action = "stack.greybeard.enabled"' in CONFIG
    and 'Action = "stack.cursedCaptain.enabled"' in CONFIG
    and 'Action = "stack.fruit.enabled"' in CONFIG
    and 'Action = "stack.berry.enabled"' in CONFIG
    and 'Action = "stack.hop.eliteHunter.enabled"' in CONFIG
    and 'Action = "stack.hop.berry.enabled"' in CONFIG
    and 'ParentSetting = "AutoEliteHunter"' in CONFIG
    and 'ParentSetting = "AutoCollectBerries"' in CONFIG
    and CONFIG.index('Action = "stack.eliteHunter.enabled"')
    < CONFIG.index('Action = "stack.hop.eliteHunter.enabled"')
    and CONFIG.index('Action = "stack.berry.enabled"')
    < CONFIG.index('Action = "stack.hop.berry.enabled"')
    and "SpecialHop" not in CONFIG,
    "hop controls must be children directly below their corresponding Stack Farming parents",
)
require(
    "AutoAttackCakePrince = false" in CONFIG
    and "AutoEliteHunter = false" in CONFIG
    and "AttackRipIndra = false" in CONFIG
    and "AttackSoulReaper = false" in CONFIG
    and "AttackDoughKing = false" in CONFIG
    and "AttackDarkbeard = false" in CONFIG
    and "AttackSaw = false" in CONFIG
    and "AttackGreybeard = false" in CONFIG
    and "AttackCursedCaptain = false" in CONFIG
    and "TeleportToFruit = false" in CONFIG
    and "AutoCollectBerries = false" in CONFIG
    and "AutoFactoryRaid = false" in CONFIG
    and "AutoCastleRaid = false" in CONFIG
    and "HopForEliteHunter = false" in CONFIG
    and "HopForBerries = false" in CONFIG,
    "Stack Farming tasks must default to off",
)
require(
    'Action = "stack.factoryRaid.enabled"' in CONFIG
    and 'Setting = "AutoFactoryRaid"' in CONFIG
    and 'Action = "stack.castleRaid.enabled"' in CONFIG
    and 'Setting = "AutoCastleRaid"' in CONFIG
    and 'Label = "Raids",\n                    RequiredSea = 2' in CONFIG
    and 'Label = "Raids",\n                    RequiredSea = 3' in CONFIG
    and CONFIG.count("RequiredSea = 2") >= 2
    and CONFIG.count("RequiredSea = 3") >= 6,
    "Factory and Castle Raid controls should be available only in their respective seas",
)
require(
    'Label = "Bosses"' in CONFIG
    and 'Label = "Second Sea"' not in CONFIG
    and 'Label = "Third Sea"' not in CONFIG
    and 'Setting = "AttackDarkbeard"' in CONFIG
    and 'Setting = "AttackRipIndra"' in CONFIG
    and 'Setting = "AttackSoulReaper"' in CONFIG
    and 'Setting = "AttackDoughKing"' in CONFIG
    and CONFIG.count('Setting = "AttackDarkbeard"') == 1
    and "RequiredSea = 2" in CONFIG
    and CONFIG.count("RequiredSea = 3") >= 5,
    "boss settings should share one heading and hide sea-specific options outside their sea",
)
require(
    "PrioritizeRipIndra = false" in CONFIG
    and "PrioritizeDoughKing = false" in CONFIG
    and 'Action = "stack.ripIndra.prioritize"' in CONFIG
    and 'Action = "stack.doughKing.prioritize"' in CONFIG
    and 'Description = "Choose Indra before Dough King when both are enabled."' in CONFIG
    and "Conjured Cocoa" in CONFIG,
    "boss priority controls should default off and explain their mutually exclusive priority",
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
    and 'folder.ChildAdded:Connect(function(instance)' in QUEUE
    and 'replicatedStorage.ChildAdded:Connect(function(instance)' in QUEUE
    and "function StackTaskQueue:BindLiveEliteTarget" in QUEUE
    and 'self:_ObserveEliteHunter(instance)' in QUEUE,
    "Elite Hunter should detect both reference sources and bind combat to its live world model",
)
require(
    '["rip_indra True Form"] = "RipIndra"' in QUEUE
    and '["Soul Reaper"] = "SoulReaper"' in QUEUE
    and '["Dough King"] = "DoughKing"' in QUEUE
    and '["Darkbeard"] = "Darkbeard"' in QUEUE
    and '["Core"] = "FactoryRaid"' in QUEUE
    and "function StackTaskQueue:_ObserveSpawnedBoss" in QUEUE
    and "self:_ObserveSpawnedBoss(instance)" in QUEUE
    and "isSpawnedStackBoss(instance)" in QUEUE,
    "spawned boss stack tasks must discover Enemy models without summoning actions",
)
require(
    '["The Saw"] = "Saw"' in QUEUE
    and '["Greybeard"] = "Greybeard"' in QUEUE
    and '["Cursed Captain"] = "CursedCaptain"' in QUEUE
    and all(f"{kind} = true" in QUEUE for kind in ("Saw", "Greybeard", "CursedCaptain"))
    and all(
        f"self.Enabled.{kind} == true" in QUEUE
        for kind in ("Saw", "Greybeard", "CursedCaptain")
    ),
    "First and Second Sea live bosses should enter the shared stack task queue",
)
require(
    "function StackTaskQueue:_ObserveCastleRaid(instance)" in QUEUE
    and "CASTLE_RAID_CENTER = Vector3.new(-5543, 313, -2964)" in QUEUE
    and "CASTLE_RAID_RADIUS = 1000" in QUEUE
    and "self:_ObserveCastleRaid(instance)" in QUEUE
    and 'elseif kind == "CastleRaid" then' in QUEUE
    and "CastleRaid" in QUEUE[QUEUE.index("function StackTaskQueue:HasEnabledTasks()") :],
    "Castle Raid should queue live eligible enemies near the Castle in the shared event queue",
)
require(
    "function StackTaskQueue:TakePendingKind(kind)" in QUEUE
    and "table.remove(self.Pending, index)" in QUEUE
    and "function MainFarm:_ChooseStackPreparation()" in MAIN_FARM
    and "function MainFarm:_StepStackPreparation(session, root, prep)" in MAIN_FARM
    and "self.StackTaskQueue:TakePendingKind(bossQueueKind)" in MAIN_FARM,
    "summon preparation should claim its own spawned boss without reordering unrelated queued jobs",
)
require(
    "return \"ChaliceChoice\", \"God's Chalice\"" in MAIN_FARM
    and 'if prep.Kind == "ChaliceChoice" then' in MAIN_FARM
    and '"Checking Haki colors to choose Indra or Dough King"' in MAIN_FARM
    and "INDRA_COLOR_REQUEST_TIMEOUT = 6" in MAIN_FARM
    and "MAX_INDRA_COLOR_REQUEST_ATTEMPTS = 2" in MAIN_FARM
    and "for _, color in pairs(colors) do" in MAIN_FARM
    and "if colorState.Failed then" in MAIN_FARM
    and "Choose an Indra or Dough King priority to continue." in MAIN_FARM
    and 'if not entry and self.ActiveStackPrep then' in MAIN_FARM
    and MAIN_FARM.index('if not entry and self.ActiveStackPrep then')
    < MAIN_FARM.index("if not entry then\n        local hopService = self.ServerHopService"),
    "a held God's Chalice must reserve Stack priority while color lookup is pending, time out safely, and avoid guessing after lookup failure",
)
require(
    "function MainFarm:_ShouldDeferServerHop()" in MAIN_FARM
    and "if self.ActiveStackTask or self.ActiveStackPrep then" in MAIN_FARM
    and "if queue and type(queue.Pending) == \"table\" and #queue.Pending > 0 then" in MAIN_FARM
    and "return self:_ShouldDeferServerHop()" in MAIN_FARM
    and "shouldDeferHop" in HOP
    and "if not self.InFlight and self:_ShouldDeferHop() then" in HOP
    and 'A Stack task is ready; finishing it before looking for another server' in HOP,
    "server hopping must yield to any active or queued Stack task before searching or joining",
)
require(
    '["Soul Reaper"] = "SoulReaper"' in QUEUE
    and "self:_Queue(kind, instance)" in QUEUE
    and 'self:_Queue("CastleRaid", instance)' in QUEUE
    and "function StackTaskQueue:_ObserveCastleRaid(instance)" in QUEUE
    and "self:_ObserveSpawnedBoss(instance)" in QUEUE
    and "self:_ObserveCastleRaid(instance)" in QUEUE,
    "Soul Reaper and Castle Raid detections must enter the same pending Stack queue that pauses hopping",
)
require(
    "CakePrince = 3" in MAIN_FARM
    and 'isStackTaskAvailableInCurrentSea(' in MAIN_FARM
    and "cakePrinceRequested and cakePrinceAvailable" in MAIN_FARM,
    "Cake Prince automation should remain disabled outside its Third Sea",
)
require(
    "FactoryRaid = 2" in MAIN_FARM
    and "CastleRaid = 3" in MAIN_FARM
    and "Saw = 1" in MAIN_FARM
    and "Greybeard = 1" in MAIN_FARM
    and "CursedCaptain = 2" in MAIN_FARM
    and 'requiredSea == 1 and "IsFirstSea"' in MAIN_FARM
    and 'Setting = "AutoFactoryRaid"' in MAIN_FARM
    and 'Setting = "AutoCastleRaid"' in MAIN_FARM
    and 'actionId == "stack.factoryRaid.enabled"' in MAIN_FARM
    and 'actionId == "stack.castleRaid.enabled"' in MAIN_FARM,
    "raid jobs should share Stack Farming's sea checks, settings, and action routing",
)
require(
    all(
        f'{{ Kind = "{kind}", Setting = "{setting}" }}' in MAIN_FARM
        for kind, setting in (
            ("Saw", "AttackSaw"),
            ("Greybeard", "AttackGreybeard"),
            ("CursedCaptain", "AttackCursedCaptain"),
        )
    )
    and all(f'settingStackTask' not in CONFIG for _ in (0,))
    and all(
        f'Action = "stack.{action}.enabled",\n'
        f'                    Setting = "{setting}",\n'
        f'                    SettingsKey = "StackFarmSettings",\n'
        f'                    RequiredSea = {sea},' in CONFIG
        for action, setting, sea in (
            ("saw", "AttackSaw", 1),
            ("greybeard", "AttackGreybeard", 1),
            ("cursedCaptain", "AttackCursedCaptain", 2),
        )
    ),
    "Saw and Greybeard must be First Sea-only; Cursed Captain must be Second Sea-only",
)
require(
    "stackSettings.AutoFactoryRaid = false" in MAIN_FARM
    and "stackSettings.AutoCastleRaid = false" in MAIN_FARM
    and 'self.StackTaskQueue:SetEnabled("FactoryRaid", false)' in MAIN_FARM
    and 'self.StackTaskQueue:SetEnabled("CastleRaid", false)' in MAIN_FARM,
    "raid toggles and queued jobs should be cleared when the hub is cleaned up",
)
require(
    'compatibility:GetInventoryMaterialCount("Conjured Cocoa")' in MAIN_FARM
    and "if count < 10 then" in MAIN_FARM
    and 'commF:InvokeServer("getColors")' in MAIN_FARM
    and 'commF:InvokeServer("activateColor", color.HiddenName)' in MAIN_FARM
    and '"Hallow Essence"' in MAIN_FARM
    and '"Fist of Darkness"' in MAIN_FARM
    and "SweetChaliceNpc" in MAIN_FARM,
    "summon preparation should use held summon items, cocoa inventory, and the referenced Indra pad flow",
)
require(
    '"DoughKingSpawnerProgress"' in MAIN_FARM
    and '"CakePrinceSpawner",\n                true' in MAIN_FARM
    and 'string.find(\n                string.lower(response),\n                "open the portal"' in MAIN_FARM
    and '"DoughKingPortal"' in MAIN_FARM
    and '("Farming Cake Land enemies; " .. tostring(remaining) .. " left")' in MAIN_FARM
    and 'local cocoaProfile = table.clone(profile)' in MAIN_FARM
    and 'cocoaProfile.BossName = nil' in MAIN_FARM,
    "Dough King preparation should read the server's 500-enemy progress and only summon when the portal is ready",
)
require(
    "if payload and stackSettings[parentSetting] ~= true then" in MAIN_FARM
    and "PrioritizeRipIndra = false" in MAIN_FARM
    and "PrioritizeDoughKing = false" in MAIN_FARM
    and "Waiting for another player to press the missing Haki pads" in MAIN_FARM,
    "priorities must require their parent toggle, stay exclusive, and wait safely for other players' pads",
)
require(
    'if payload and stackSettings[localSettingKey] ~= true then' in MAIN_FARM
    and 'stackSettings.HopForEliteHunter = false' in MAIN_FARM
    and 'stackSettings.HopForBerries = false' in MAIN_FARM,
    "server hopping must require its parent toggle and turn off when its parent is disabled",
)
require(
    "instance.Parent == self.EnemiesFolder" in QUEUE
    and "isSpawnedBossKind(entry.Kind)" in QUEUE
    and "isStackTaskAvailableInCurrentSea" in MAIN_FARM
    and 'Kind = "Darkbeard", Setting = "AttackDarkbeard"' in MAIN_FARM
    and 'Kind = "RipIndra", Setting = "AttackRipIndra"' in MAIN_FARM,
    "new boss jobs must be sea-gated and use live spawned enemies",
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
    and '"TrackedQuestFrame"' in MAIN_FARM
    and '"description"' in MAIN_FARM
    and 'self:_EngageModeTarget(target, true, root, session, "stack")' in MAIN_FARM
    and "Elite Hunter quest accepted; waiting for the target to load" in MAIN_FARM
    and "BindLiveEliteTarget(entry, liveTarget)" in MAIN_FARM
    and "target:IsDescendantOf(self.StackTaskQueue.ReplicatedStorage)" in MAIN_FARM
    and "STACK_TASK_SEA_REQUIREMENTS" in MAIN_FARM
    and '"IsSecondSea"' in MAIN_FARM
    and "isStackTaskAvailableInCurrentSea" in MAIN_FARM
    and "or self.Enabled.EliteHunter == true" in QUEUE,
    "Elite Hunter must confirm the Sea 3 tracked quest, attack the reference-resolved target, and use shared combat",
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
    "coordinator:TryAcquire(" in TELEPORT
    and '"Background"' in TELEPORT
    and "function(preemptingGroup, preemptingLabel)" in TELEPORT
    and "Stack Farming is waiting for " in MAIN_FARM
    and "coordinator:CanRunStack(self.ActiveStackLease)" in MAIN_FARM,
    "manual travel is low priority while task-owned travel remains under its task lease",
)
require(
    all(setting in MAIN_FARM for setting in (
        "AutoCollectBerries",
        "AutoEliteHunter",
        "HopForEliteHunter",
        "HopForBerries",
        "AttackRipIndra",
        "AttackSoulReaper",
        "AttackDoughKing",
        "AttackDarkbeard",
    ))
    and "TaskCoordinator" in TELEPORT,
    "all Stack Farming jobs must use shared task ownership rather than per-toggle travel checks",
)

print("PASS: Main Farming and Stack Farming are separate nested pages")
print("PASS: stack jobs share one worker; fruit batches use gateway-aware route ordering")
print("PASS: standalone stack jobs and travel conflict handling are wired")
print("PASS: Stack Farming server search runs through the shared task queue")
