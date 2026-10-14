from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATE = (ROOT / "src/ReplicatedStorage/CustomHub/State.lua").read_text(encoding="utf-8")
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text(encoding="utf-8")
TELEPORT = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua"
).read_text(encoding="utf-8")
MAIN_FARM = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


require(
    "notification = self._values.notification" in STATE
    and "function State:_QueueErrorNotification(playerMessage)" in STATE
    and 'if kind == "error" then' in STATE
    and '"That action couldn\'t be completed. Check the hub status line for details."' in STATE,
    "State must expose a player-readable error notification and keep generic errors non-technical",
)
require(
    'Name = "ActionErrorNotification"' in UI
    and "AnchorPoint = Vector2.new(1, 1)" in UI
    and "UDim2.new(1, -16, 1, -16)" in UI
    and "self:_ShowNotification(snapshot.notification)" in UI
    and "task.delay(4.5" in UI
    and "theme.Error" in UI,
    "the error toast must use the hub theme, appear bottom-right, and dismiss automatically",
)
require(
    "Turn off Start Farm first. Travel and farming can't run together." in TELEPORT
    and "Turn off the current travel switch before starting a different trip." in TELEPORT
    and "Turn off Travel to Island or Travel to NPC before starting Auto Farm." in MAIN_FARM
    and 'return false, "Manual travel is active"' in MAIN_FARM,
    "conflicting travel and farming actions must be blocked with plain-language reasons",
)

print("PASS: bottom-right error toasts and clear travel/farming conflict messages")
