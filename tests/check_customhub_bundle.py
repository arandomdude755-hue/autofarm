#!/usr/bin/env python3
"""Static completeness checks for the generated single-LocalScript bundle."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
BUNDLE_PATH = ROOT / "dist/customhub.bundle.lua"
SOURCE_COMMIT = "82dfb4ced51c3dea30d25e5fa891c42928ef62c7"

SOURCE_FILES = (
    "src/ReplicatedStorage/CustomHub/Config.lua",
    "src/ReplicatedStorage/CustomHub/State.lua",
    "src/ReplicatedStorage/CustomHub/Compatibility.lua",
    "src/ReplicatedStorage/CustomHub/FeatureManager.lua",
    "src/ReplicatedStorage/CustomHub/UI.lua",
    "src/ReplicatedStorage/CustomHub/Features/PlaceholderFeatures.lua",
    "src/ReplicatedStorage/CustomHub/Features/Farm/QuestService.lua",
    "src/ReplicatedStorage/CustomHub/Features/Farm/EnemyService.lua",
    "src/ReplicatedStorage/CustomHub/Features/Farm/MovementService.lua",
    "src/ReplicatedStorage/CustomHub/Features/Farm/CombatService.lua",
    "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua",
    "src/ReplicatedStorage/CustomHub/init.lua",
)

MODULE_IDS = {
    "CustomHub.Config",
    "CustomHub.State",
    "CustomHub.Compatibility",
    "CustomHub.FeatureManager",
    "CustomHub.UI",
    "CustomHub.Features.PlaceholderFeatures",
    "CustomHub.Features.Farm.QuestService",
    "CustomHub.Features.Farm.EnemyService",
    "CustomHub.Features.Farm.MovementService",
    "CustomHub.Features.Farm.CombatService",
    "CustomHub.Features.MainFarm",
    "CustomHub",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


require(BUNDLE_PATH.is_file(), "generated bundle does not exist; run tools/bundle_customhub.py")
bundle = BUNDLE_PATH.read_text(encoding="utf-8")
require(f"Source commit: {SOURCE_COMMIT}" in bundle, "bundle source commit marker is incorrect")

factory_ids = set(
    re.findall(r'__bundleFactories\["([^"]+)"\]\s*=\s*function\(\)', bundle)
)
require(factory_ids == MODULE_IDS, f"factory/module mismatch: missing={MODULE_IDS - factory_ids}, extra={factory_ids - MODULE_IDS}")

for source_file in SOURCE_FILES:
    require(
        bundle.count(f"-- BEGIN SOURCE: {source_file}") == 1
        and bundle.count(f"-- END SOURCE: {source_file}") == 1,
        f"source module missing or duplicated: {source_file}",
    )

named_loads = set(re.findall(r'__bundleLoad\("([^"]+)"\)', bundle))
require(
    named_loads <= factory_ids,
    f"internal module reference has no factory: {named_loads - factory_ids}",
)
require(not re.search(r"require\s*\(\s*script(?:\.|\s*\))", bundle),
        "unbundled ModuleScript-relative require remains")
require(
    'require(ReplicatedStorage:WaitForChild("CustomHub"))' not in bundle,
    "client entrypoint still requires a ReplicatedStorage CustomHub instance",
)

external_require_arguments = set(
    re.findall(r"\bpcall\s*\(\s*require\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", bundle)
)
expected_external_require_arguments = {
    "questsModule",
    "guideModule",
    "mouseModule",
    "combatUtilModule",
    "netModule",
}
require(
    external_require_arguments == expected_external_require_arguments,
    "unexpected external require set: "
    f"{external_require_arguments}; expected {expected_external_require_arguments}",
)

require('__bundleLoad("CustomHub")' in bundle, "bundled LocalScript entrypoint is missing")
require("script.Destroying:Connect(function()" in bundle and "hub:Destroy()" in bundle,
        "entrypoint cleanup hook is missing")
require("local __bundleCache = {}" in bundle and "__bundleCache[moduleName] = value" in bundle,
        "module cache is missing")

print(f"PASS: all {len(MODULE_IDS)} internal modules and the LocalScript entrypoint are bundled")
print(f"PASS: all named internal references resolve; external runtime requires are exactly {sorted(external_require_arguments)}")
print("PASS: initialization, caching, and LocalScript cleanup are present")
