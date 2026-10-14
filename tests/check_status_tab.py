from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text()
STATE = (ROOT / "src/ReplicatedStorage/CustomHub/State.lua").read_text()
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text()
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/StatusFeature.lua").read_text()
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text()


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


require(
    '"StatusServer"' in CONFIG
    and 'Title = "Status & Server"' in CONFIG
    and 'tabName == "StatusServer" and "Status"' in UI
    and 'Action = "status.refresh"' in CONFIG
    and 'Action = "status.copy"' in CONFIG,
    "Status & Server tab exposes refresh and copy actions",
)
require(
    'Kind = "statusValue"' in CONFIG
    and "statusValues = statusValues" in STATE
    and "function State:SetStatusValues(values)" in STATE
    and "snapshot.statusValues[entry.Key]" in UI,
    "read-only status rows update from isolated state snapshots",
)
require(
    "function StatusFeature:_ReadValues()" in FEATURE
    and "function StatusFeature:_BuildReport(values)" in FEATURE
    and 'values.fullJobId' in FEATURE
    and 'context.State:SetStatusValues(self:_ReadValues())' in FEATURE
    and "StatusFeature" in MANAGER,
    "status report gathers local player and server data without invoking remotes",
)
require(
    "StatusValueEntries" in UI
    and 'control.Kind == "statusValue"' in UI
    and "Name = self:_ControlNodeName(control)" in UI,
    "status rows use the existing hub card style and refresh lifecycle",
)
