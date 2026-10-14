from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text(encoding="utf-8")
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text(encoding="utf-8")
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua").read_text(
    encoding="utf-8"
)
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
    and "function TeleportFeature:Cancel(message)" in FEATURE,
    "travel and Auto Farm conflicts must be blocked with player-facing explanations",
)
require(
    "MovementService.new(compatibility" in MANAGER
    and "MovementService = movementService" in MANAGER
    and "MovementService = context.MovementService" in FEATURE,
    "Farm and Travel must share one movement controller",
)
require(
    "player.CharacterRemoving:Connect" in FEATURE
    and "LastStallAt ~= request.LastStallAt" in FEATURE
    and "copy the status report for movement details" in FEATURE,
    "travel must stop on character reset and surface movement stalls",
)
require(
    "local MAX_STALL_RETRIES = 2" in FEATURE
    and "request.StallRetries += 1" in FEATURE
    and "task.wait(STALL_RETRY_DELAY)" in FEATURE
    and "issueMovement" in FEATURE
    and "Travel stalled after " in FEATURE,
    "manual travel must retry a transient movement stall a bounded number of times",
)
require(
    "TeleportService" not in FEATURE
    and 'Action = "teleport.status"' not in CONFIG,
    "manual travel must not add server hopping or the old placeholder",
)
require(
    'Name = "Hydra House"' in CONFIG
    and "Position = Vector3.new(5245, 602, 251)" in CONFIG
    and "SurfaceSnap = true" in CONFIG
    and "if destination.SurfaceSnap == true then" in FEATURE
    and "workspace:Raycast(origin, Vector3.new(0, -2400, 0), params)" in FEATURE
    and "return CFrame.new(destination.Position + Vector3.new(0, 18, 0))" in FEATURE,
    "island travel must use exact reference coordinates and resolve Hydra House onto a real surface",
)

print("PASS: toggle-based island/NPC travel, reference NPC fallback, Hydra surface resolution, and shared movement ownership")
