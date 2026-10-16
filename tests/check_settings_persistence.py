from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERSISTENCE = (ROOT / "src/ReplicatedStorage/CustomHub/SettingsPersistence.lua").read_text(
    encoding="utf-8"
)
HUB = (ROOT / "src/ReplicatedStorage/CustomHub/init.lua").read_text(encoding="utf-8")
FEATURE_MANAGER = (
    ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(
    "local SCHEMA_VERSION = 2" in PERSISTENCE
    and "function SettingsPersistence:Load()" in PERSISTENCE
    and "function SettingsPersistence:ScheduleSave()" in PERSISTENCE
    and "function SettingsPersistence:Flush()" in PERSISTENCE,
    "settings persistence needs versioned load, debounced save, and shutdown flush",
)
require(
    "SettingsPersistence.new(Config, compatibility)" in HUB
    and "settingsPersistence:Load()" in HUB
    and "settingsPersistence:SetState(state)" in HUB,
    "saved settings must load before feature initialization and UI state creation",
)
require(
    "function Hub:Destroy()" in HUB
    and "self.SettingsPersistence:Flush()" in HUB[HUB.index("function Hub:Destroy()"):]
    and HUB[HUB.index("function Hub:Destroy()"):].index("self.SettingsPersistence:Flush()")
    < HUB[HUB.index("function Hub:Destroy()"):].index("self.FeatureManager:Cleanup()"),
    "pending settings must flush before feature cleanup resets runtime task flags",
)
require(
    "featureEnabled" not in PERSISTENCE
    and "statusValues" not in PERSISTENCE
    and "ActiveStackTask" not in PERSISTENCE,
    "transient automation state must not be restored from the saved preferences file",
)
require(
    "function SettingsPersistence:SetHopSession(session)" in PERSISTENCE
    and "function SettingsPersistence:GetHopSession()" in PERSISTENCE
    and "function SettingsPersistence:CanPersistHopSession()" in PERSISTENCE,
    "only a pending hop token may resume a search after a server teleport",
)
require(
    "function FeatureManager:_ScheduleSettingsSave()" in FEATURE_MANAGER
    and "self:_ScheduleSettingsSave()" in FEATURE_MANAGER,
    "successful settings actions must schedule a debounced save",
)
require(
    'SETTINGS_FOLDER .. "/settings_" .. tostring(userId) .. ".json"' in PERSISTENCE
    and 'type(setting) == "string"' in PERSISTENCE,
    "settings files must be per-user and load only known UI setting keys",
)

print("PASS: versioned per-user settings load/save and transient-state exclusion")
