#!/usr/bin/env python3
"""Build a single-LocalScript bundle from the checked-out CustomHub source tree."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "dist/customhub.bundle.lua"

MODULES = (
    ("CustomHub.Config", "src/ReplicatedStorage/CustomHub/Config.lua", {}),
    ("CustomHub.State", "src/ReplicatedStorage/CustomHub/State.lua", {}),
    ("CustomHub.Compatibility", "src/ReplicatedStorage/CustomHub/Compatibility.lua", {}),
    (
        "CustomHub.SettingsPersistence",
        "src/ReplicatedStorage/CustomHub/SettingsPersistence.lua",
        {},
    ),
    (
        "CustomHub.FeatureManager",
        "src/ReplicatedStorage/CustomHub/FeatureManager.lua",
        {
            "require(script.Features.PlaceholderFeatures)": '__bundleLoad("CustomHub.Features.PlaceholderFeatures")',
            "require(script.Features.MainFarm)": '__bundleLoad("CustomHub.Features.MainFarm")',
            "require(script.Features.TeleportFeature)": '__bundleLoad("CustomHub.Features.TeleportFeature")',
            "require(script.Features.StatusFeature)": '__bundleLoad("CustomHub.Features.StatusFeature")',
            "require(script.Features.Farm.MovementService)": '__bundleLoad("CustomHub.Features.Farm.MovementService")',
        },
    ),
    ("CustomHub.UI", "src/ReplicatedStorage/CustomHub/UI.lua", {}),
    (
        "CustomHub.Features.StatusFeature",
        "src/ReplicatedStorage/CustomHub/Features/StatusFeature.lua",
        {},
    ),
    (
        "CustomHub.Features.PlaceholderFeatures",
        "src/ReplicatedStorage/CustomHub/Features/PlaceholderFeatures.lua",
        {},
    ),
    (
        "CustomHub.Features.MapGatewayService",
        "src/ReplicatedStorage/CustomHub/Features/MapGatewayService.lua",
        {},
    ),
    (
        "CustomHub.Features.TeleportFeature",
        "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua",
        {
            "require(script.Parent.MapGatewayService)": '__bundleLoad("CustomHub.Features.MapGatewayService")',
        },
    ),
    (
        "CustomHub.Features.Farm.QuestService",
        "src/ReplicatedStorage/CustomHub/Features/Farm/QuestService.lua",
        {},
    ),
    (
        "CustomHub.Features.Farm.EnemyService",
        "src/ReplicatedStorage/CustomHub/Features/Farm/EnemyService.lua",
        {},
    ),
    (
        "CustomHub.Features.Farm.MovementService",
        "src/ReplicatedStorage/CustomHub/Features/Farm/MovementService.lua",
        {},
    ),
    (
        "CustomHub.Features.Farm.SkillAimRedirect",
        "src/ReplicatedStorage/CustomHub/Features/Farm/SkillAimRedirect.lua",
        {},
    ),
    (
        "CustomHub.Features.Farm.CombatService",
        "src/ReplicatedStorage/CustomHub/Features/Farm/CombatService.lua",
        {
            "require(script.Parent.SkillAimRedirect)": '__bundleLoad("CustomHub.Features.Farm.SkillAimRedirect")',
        },
    ),
    (
        "CustomHub.Features.Farm.StackTaskQueue",
        "src/ReplicatedStorage/CustomHub/Features/Farm/StackTaskQueue.lua",
        {},
    ),
    (
        "CustomHub.Features.MainFarm",
        "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua",
        {
            "require(script.Parent.Farm.QuestService)": '__bundleLoad("CustomHub.Features.Farm.QuestService")',
            "require(script.Parent.Farm.EnemyService)": '__bundleLoad("CustomHub.Features.Farm.EnemyService")',
            "require(script.Parent.Farm.MovementService)": '__bundleLoad("CustomHub.Features.Farm.MovementService")',
            "require(script.Parent.Farm.CombatService)": '__bundleLoad("CustomHub.Features.Farm.CombatService")',
            "require(script.Parent.Farm.StackTaskQueue)": '__bundleLoad("CustomHub.Features.Farm.StackTaskQueue")',
        },
    ),
    (
        "CustomHub",
        "src/ReplicatedStorage/CustomHub/init.lua",
        {
            "require(script.Config)": '__bundleLoad("CustomHub.Config")',
            "require(script.State)": '__bundleLoad("CustomHub.State")',
            "require(script.Compatibility)": '__bundleLoad("CustomHub.Compatibility")',
            "require(script.SettingsPersistence)": '__bundleLoad("CustomHub.SettingsPersistence")',
            "require(script.FeatureManager)": '__bundleLoad("CustomHub.FeatureManager")',
            "require(script.UI)": '__bundleLoad("CustomHub.UI")',
        },
    ),
)

ENTRYPOINT_PATH = "src/StarterPlayer/StarterPlayerScripts/CustomHub.client.lua"
ENTRYPOINT_REWRITES = {
    'require(ReplicatedStorage:WaitForChild("CustomHub"))': '__bundleLoad("CustomHub")',
}


def read_source_file(relative_path: str) -> str:
    source_path = ROOT / relative_path
    if not source_path.is_file():
        raise FileNotFoundError(f"Required CustomHub source file is missing: {relative_path}")
    return source_path.read_text(encoding="utf-8")


def apply_exact_rewrites(source: str, rewrites: dict[str, str], source_name: str) -> str:
    for original, replacement in rewrites.items():
        count = source.count(original)
        if count != 1:
            raise ValueError(
                f"{source_name}: expected exactly one {original!r}, found {count}"
            )
        source = source.replace(original, replacement, 1)
    return source


def build_bundle() -> str:
    lines = [
        "-- Generated by tools/bundle_customhub.py; do not edit this file directly.",
        "-- Source files are read from the checked-out src/ tree.",
        "-- Install/run this as a client LocalScript in the intended game environment.",
        "-- External Roblox modules and services remain runtime dependencies.",
        "",
        "local __bundleFactories = {}",
        "local __bundleCache = {}",
        "",
        "local function __bundleLoad(moduleName)",
        "    local cached = __bundleCache[moduleName]",
        "    if cached ~= nil then",
        "        return cached",
        "    end",
        "",
        "    local factory = __bundleFactories[moduleName]",
        "    if not factory then",
        '        error("CustomHub bundle: unresolved internal module " .. tostring(moduleName), 2)',
        "    end",
        "",
        "    local value = factory()",
        "    if value == nil then",
        "        value = true",
        "    end",
        "    __bundleCache[moduleName] = value",
        "    return value",
        "end",
        "",
    ]

    for module_name, relative_path, rewrites in MODULES:
        source = read_source_file(relative_path)
        source = apply_exact_rewrites(source, rewrites, relative_path)
        if "require(script" in source:
            raise ValueError(f"{relative_path}: unresolved internal require remains")

        lines.extend(
            (
                f'__bundleFactories["{module_name}"] = function()',
                f"-- BEGIN SOURCE: {relative_path}",
                source.rstrip("\n"),
                f"-- END SOURCE: {relative_path}",
                "end",
                "",
            )
        )

    entrypoint = read_source_file(ENTRYPOINT_PATH)
    entrypoint = apply_exact_rewrites(
        entrypoint, ENTRYPOINT_REWRITES, ENTRYPOINT_PATH
    )
    if "require(ReplicatedStorage:WaitForChild" in entrypoint:
        raise ValueError("client entrypoint still contains an unresolved CustomHub require")

    lines.extend(
        (
            "-- BEGIN BUNDLED CLIENT ENTRYPOINT",
            entrypoint.rstrip("\n"),
            "-- END BUNDLED CLIENT ENTRYPOINT",
            "",
        )
    )
    return "\n".join(lines)


def main() -> None:
    bundle = build_bundle()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(bundle, encoding="utf-8", newline="\n")
    print(f"Generated {OUTPUT.relative_to(ROOT)} from checked-out CustomHub sources")
    print(f"Included {len(MODULES)} CustomHub ModuleScripts and the LocalScript entrypoint")


if __name__ == "__main__":
    main()
