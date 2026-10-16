from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text()
MAIN_FARM = (ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua").read_text()
TELEPORT = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua").read_text()
PERSISTENCE = (ROOT / "src/ReplicatedStorage/CustomHub/SettingsPersistence.lua").read_text()
COORDINATOR = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TaskCoordinator.lua").read_text()
COMPAT = (ROOT / "src/ReplicatedStorage/CustomHub/Compatibility.lua").read_text()
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text()

assert '{ Label = "Farming Other", Page = "FarmOther" }' in CONFIG
assert '"Auto unlock Sea 2"' in CONFIG and '"Auto unlock Sea 3"' in CONFIG
assert 'Action = "progression.trevor.offerFruit"' in CONFIG
assert "Offer selected fruit to Trevor (consumes it)" in CONFIG
assert 'Action = "teleport.sea"' in CONFIG
assert 'Options = { "First Sea", "Second Sea", "Third Sea" }' in CONFIG

assert '"DressrosaQuestProgress"' in MAIN_FARM
assert '"TravelDressrosa"' in MAIN_FARM
assert '"BartiloQuestProgress"' in MAIN_FARM
assert '"GetUnlockables"' in MAIN_FARM
assert '"ZQuestProgress"' in MAIN_FARM
assert '"TravelZou"' in MAIN_FARM
assert '"TalkTrevor", "1"' in MAIN_FARM
assert "ResumePendingSeaProgression" in MAIN_FARM
assert "ResumeMainFarmAfterSeaUnlock" in MAIN_FARM
assert "AutoUnlockSea2" in PERSISTENCE and "AutoUnlockSea3" in PERSISTENCE
assert "ResumeSea" in PERSISTENCE
assert "ResumePendingSeaProgression" in MANAGER
assert 'group == "StackFarm" or group == "Protected"' in COORDINATOR
assert "GetOwnedBloxFruitOptions" in COMPAT
assert "price >= 1000000" in COMPAT

assert '["First Sea"] = 1' in TELEPORT
assert '[1] = "TravelMain"' in TELEPORT
assert '[2] = "TravelDressrosa"' in TELEPORT
assert '[3] = "TravelZou"' in TELEPORT
assert "self.ActiveSeaTravel" in TELEPORT

print("PASS: Sea unlocks, explicit Trevor fruit confirmation, one-time farm resume, and official sea travel are wired")
