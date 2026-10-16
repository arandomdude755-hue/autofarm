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
    and "function State:_QueueErrorNotification(playerMessage, kind, options)" in STATE
    and 'if kind == "error" or (kind == "warning" and playerMessage ~= nil) then' in STATE
    and '"That action couldn\'t be completed. Check the hub status line for details."' in STATE
    and "local cooldown = tonumber(options.Cooldown) or 30" in STATE
    and "function State:ClearNotification(key)" in STATE
    and "self._values.notification = nil" in STATE,
    "State must deduplicate repeated issues, clear resolved alerts, and keep messages player-readable",
)
require(
    'kind == "warning" and playerMessage ~= nil' in STATE
    and '"Action needed"' in STATE
    and "Kind = notificationKind" in STATE,
    "explicit player-facing warnings must use the same notification surface with warning styling",
)
require(
    'Name = "ActionErrorNotification"' in UI
    and "AnchorPoint = Vector2.new(1, 1)" in UI
    and "UDim2.new(1, -16, 1, -16)" in UI
    and "MaxSize = Vector2.new(290, 68)" in UI
    and "MinSize = Vector2.new(190, 54)" in UI
    and "Size = UDim2.new(0.82, 0, 0, 64)" in UI
    and "self:_ShowNotification(snapshot.notification)" in UI
    and "task.delay(4.5" in UI
    and "function UI:_HideNotification()" in UI
    and "if self.CurrentNotificationPersistent then" in UI
    and "theme.Error" in UI,
    "the error toast must use the hub theme, appear bottom-right, and support persistent resolution-aware alerts",
)
require(
    'Key = "indra_missing_haki"' in MAIN_FARM
    and "Persistent = true" in MAIN_FARM
    and 'state:ClearNotification("indra_missing_haki")' in MAIN_FARM
    and "current.Persistent = current.Persistent or options.Persistent == true" in STATE,
    "Indra's missing-color alert should remain visible once and clear when its condition is resolved or cancelled",
)
require(
    "control.LockedBySetting" in UI
    and "control.LockedPlayerMessage" in UI
    and 'self.State:SetStatus(' in UI[
        UI.index("function UI:_ToggleDropdown"):
        UI.index("function UI:_UpdateSliderVisual")
    ],
    "locked dropdowns must stay visible and explain the lock when clicked",
)
require(
    "Turn off Start Farm first. Travel and farming can't run together." in TELEPORT
    and "Turn off the current travel switch before starting a different trip." in TELEPORT
    and "Turn off Travel to Island or Travel to NPC before starting Auto Farm." in MAIN_FARM
    and 'return false, "Manual travel is active"' in MAIN_FARM,
    "conflicting travel and farming actions must be blocked with plain-language reasons",
)

print("PASS: bottom-right error toasts and clear travel/farming conflict messages")
