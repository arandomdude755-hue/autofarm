from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text(encoding="utf-8")
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text(encoding="utf-8")
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua").read_text(
    encoding="utf-8"
)
GATEWAYS = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/MapGatewayService.lua"
).read_text(encoding="utf-8")
COMPATIBILITY = (
    ROOT / "src/ReplicatedStorage/CustomHub/Compatibility.lua"
).read_text(encoding="utf-8")
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text(
    encoding="utf-8"
)
MAIN_FARM = (ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua").read_text(
    encoding="utf-8"
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


require(
    all(f"[{index}] = {{" in CONFIG for index in (1, 2, 3))
    and "travelIslandsForCurrentSea" in CONFIG
    and "getCurrentSeaIndex(compatibility)" in CONFIG,
    "island destinations must be filtered to the recognized current sea",
)
require(
    'Name = "Dragon Dojo"' in CONFIG
    and "Position = Vector3.new(5700, 1210, 860)" in CONFIG
    and "ExactPosition = true" in CONFIG,
    "Dragon Dojo must appear at the requested exact Third Sea coordinates",
)
require(
    all(action in CONFIG for action in (
        'Action = "teleport.island.select"',
        'Action = "teleport.npc.select"',
        'Kind = "featureToggle"',
        'Action = "teleport.island"',
        'Action = "teleport.npc"',
    )),
    "Teleport page must use selectable destinations and independent travel toggles",
)
require(
    'Action = "teleport.cancel"' not in CONFIG
    and 'Label = "Cancel travel"' not in CONFIG
    and "self:_SetFeatureEnabled(request.Action, false)" in FEATURE
    and "self:_SetFeatureEnabled(actionId, true)" in FEATURE,
    "travel toggles must replace Cancel travel and turn off when travel finishes",
)
require(
    all(token in CONFIG for token in (
        'SettingsKey = "TravelSettings"',
        "AllowNoSelection = true",
        "travelNpcsForCurrentSea",
    )),
    "travel dropdowns must use separate settings and avoid selecting a destination implicitly",
)
require(
    "function UI:_GetControlSettings(control)" in UI
    and "control.SettingsKey or \"FarmSettings\"" in UI
    and "self:_GetControlSettings(control)" in UI,
    "the UI must support dropdowns backed by settings outside FarmSettings",
)
require(
    'replicatedStorage and replicatedStorage:FindFirstChild("NPCs")' in FEATURE
    and 'npc.Name == name' in FEATURE
    and 'npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart' in FEATURE
    and "nearestDistance" in FEATURE,
    "NPC travel must search live NPCs and ReplicatedStorage templates, preferring the live instance",
)
require(
    "mainFarm and mainFarm.Running" in FEATURE
    and "Turn off Travel to Island or Travel to NPC before starting Auto Farm." in MAIN_FARM
    and "Turn off Start Farm first. Travel and farming can't run together." in FEATURE
    and "function TeleportFeature:Cancel(message, keepActionEnabled)" in FEATURE,
    "travel and Auto Farm conflicts must be blocked with player-facing explanations",
)
require(
    "function TeleportFeature:_RetargetActiveIslandTravel()" in FEATURE
    and "self:_RetargetActiveIslandTravel()" in FEATURE
    and "self:Cancel(nil, true)" in FEATURE
    and "return self:_StartTravel(destination, island.Name, request.Action)" in FEATURE,
    "changing the Island dropdown during island travel must restart the active trip without turning its toggle off",
)
require(
    "MovementService.new(compatibility" in MANAGER
    and "MovementService = movementService" in MANAGER
    and "MovementService = context.MovementService" in FEATURE,
    "Farm and Travel must share one movement controller",
)
require(
    "player.CharacterRemoving:Connect" in FEATURE
    and "function TeleportFeature:_MoveAndWait" in FEATURE
    and "function TeleportFeature:_IsTravelCurrent" in FEATURE
    and "copy the status report for movement details" in FEATURE,
    "travel must stop on character reset and surface movement stalls",
)
require(
    "local MAX_STALL_RETRIES = 2" in FEATURE
    and "request.StallRetries = retries" in FEATURE
    and "task.wait(STALL_RETRY_DELAY)" in FEATURE
    and "self:_MoveAndWait(request, character, request.Destination)" in FEATURE
    and "Travel stalled after " in FEATURE,
    "manual travel must retry a transient movement stall a bounded number of times",
)
require(
    all(route in GATEWAYS for route in (
        "Enter Underwater City",
        "Leave Underwater City",
        "Enter Ghost Ship",
        "Leave Ghost Ship",
        "Castle to Mansion",
        "Mansion to Castle",
        "Castle to Hydra",
        "Hydra to Castle",
        "Castle to Tiki",
        "Tiki to Castle",
        "Enter Beautiful Pirate Domain",
        "Leave Beautiful Pirate Domain",
    ))
    and "MINIMUM_DISTANCE_SAVED = 1500" in GATEWAYS
    and "MAX_ROUTE_HOPS = 4" in GATEWAYS
    and "HasOwnedInventoryItem" in GATEWAYS
    and '"Valkyrie Helm"' in GATEWAYS
    and '"Feathered Visage"' in GATEWAYS,
    "map gateway routes must be sea-scoped, distance-gated, and require owned items where Vxeze does",
)
require(
    '"requestEntrance"' in GATEWAYS
    and "BoatCastleTeleporter" in GATEWAYS
    and "distance(currentRoot.Position, route.Destination) <= 200" in GATEWAYS
    and "FAILED_ROUTE_COOLDOWN = 120" in GATEWAYS
    and "Portal-Portal" not in GATEWAYS
    and "Portal Fruit" not in GATEWAYS,
    "map gateways must verify arrival, cool down failed routes, and exclude Portal Fruit",
)
require(
    "function Compatibility:CanSimulateTouch()" in COMPATIBILITY
    and "function Compatibility:TouchPart(touchingPart, targetPart, isCurrent)" in COMPATIBILITY
    and "firetouchinterest" in COMPATIBILITY
    and "self.GatewayService:Use(route" in FEATURE
    and "continuing by normal travel" in FEATURE,
    "touch-only gateways must use the guarded compatibility helper and fall back to normal travel",
)
require(
    "for _, item in itemService:GetItems(quantityKey) do" in COMPATIBILITY
    and "for item in itemService:GetItems(quantityKey) do" not in COMPATIBILITY,
    "inventory ownership scans must read the item record yielded as GetItems' second value",
)
require(
    "function MapGatewayService:BuildDiagnosticReport()" in GATEWAYS
    and "function MapGatewayService:RecordTravelPhase(phase, route, details)" in GATEWAYS
    and "RemoteCallStatus" in GATEWAYS
    and "DistanceAfterActivation" in GATEWAYS
    and "Candidate " in GATEWAYS
    and "function TeleportFeature:BuildGatewayDiagnosticReport()" in FEATURE,
    "gateway diagnostics must distinguish planning, approach, activation, and arrival failures",
)
require(
    "local GATEWAY_ACTIVATION_TIMEOUT = 8" in GATEWAYS
    and "local REMOTE_RETRY_INTERVAL = 0.3" in GATEWAYS
    and "remoteCallCount += 1" in GATEWAYS
    and "and os.clock() - lastRemoteCallAt >= REMOTE_RETRY_INTERVAL" in GATEWAYS,
    "requestEntrance must retry at the Vxeze cadence until arrival or the bounded timeout",
)
farm_navigation = FEATURE[
    FEATURE.index("function TeleportFeature:MoveFarmTo("):
    FEATURE.index("\nfunction TeleportFeature:_StartTravel(")
]
farm_move = MAIN_FARM[
    MAIN_FARM.index("function MainFarm:_MoveTo("):
    MAIN_FARM.index("\nfunction MainFarm:_HoldPosition(")
]
require(
    "function TeleportFeature:MoveFarmTo(destination, options)" in farm_navigation
    and "self.GatewayService.FindPlan" in farm_navigation
    and "RoutePlan = routePlan" in farm_navigation
    and "task.spawn(function()" in farm_navigation
    and "pcall(self._RunTravel, self, request, character)" in farm_navigation
    and "teleportFeature:MoveFarmTo(destination" in farm_move
    and "Label = \"farm target\"" in farm_move
    and "self.ActiveFarmTravel == request" in FEATURE
    and "self:CancelFarmTravel(true)" in FEATURE,
    "all MainFarm travel must reuse the same distance planner, route executor, and cancellation handling as travel-tab routes",
)
title_diagnostic = COMPATIBILITY[
    COMPATIBILITY.index("function Compatibility:BuildTitleAccessDiagnosticReport()"):
    COMPATIBILITY.index("\nfunction Compatibility:GetCombatDependencies()")
]
require(
    "Liberator of the Sky" in title_diagnostic
    and "Player.Data" in title_diagnostic
    and "PlayerGui" in title_diagnostic
    and 'scanRoot("TitlesMenu", titlesMenu, 10000, true, true)' in title_diagnostic
    and 'scanRoot("PlayerGui exact-title scan", playerGui, 10000, false, false)' in title_diagnostic
    and 'FindFirstChild("CommF_")' in title_diagnostic
    and "Generic CommF_ remote:" in title_diagnostic
    and "RemoteFunction" in title_diagnostic
    and "generic remote; not invoked" in title_diagnostic
    and "InvokeServer" not in title_diagnostic
    and "FireServer" not in title_diagnostic
    and "BuildTitleAccessDiagnosticReport" in MAIN_FARM,
    "title-access diagnostics must inspect client state and remote names without invoking unknown remotes",
)
require(
    "TeleportService" not in FEATURE
    and 'Action = "teleport.status"' not in CONFIG,
    "manual travel must not add server hopping or the old placeholder",
)
require(
    'Name = "Hydra Town"' in CONFIG
    and "Position = Vector3.new(5290, 1005.4, 393.6)" in CONFIG
    and "ExactPosition = true" in CONFIG
    and "if destination.ExactPosition == true then" in FEATURE
    and "return CFrame.new(destination.Position)" in FEATURE
    and "return CFrame.new(destination.Position + Vector3.new(0, 18, 0))" in FEATURE,
    "Hydra Town must use the requested exact coordinates without the normal vertical offset",
)

print("PASS: toggle-based island/NPC travel, reference NPC fallback, exact Hydra Town destination, and shared movement ownership")
