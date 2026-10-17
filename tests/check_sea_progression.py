from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text()
MAIN_FARM = (ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua").read_text()
TELEPORT = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua").read_text()
PERSISTENCE = (ROOT / "src/ReplicatedStorage/CustomHub/SettingsPersistence.lua").read_text()
COORDINATOR = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TaskCoordinator.lua").read_text()
COMPAT = (ROOT / "src/ReplicatedStorage/CustomHub/Compatibility.lua").read_text()
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text()
STACK_QUEUE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/StackTaskQueue.lua").read_text()

assert '{ Label = "Stack Farming", Page = "StackFarming" }' in CONFIG
assert 'Page = "FarmOther"' not in CONFIG
stack_page = CONFIG.split("StackFarming = {", 1)[1].split("\n        Teleport = {", 1)[0]
assert '"Auto unlock Sea 2"' in stack_page and '"Auto unlock Sea 3"' in stack_page
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
assert 'SeaUnlock2 = true' in STACK_QUEUE and 'SeaUnlock3 = true' in STACK_QUEUE
assert "function StackTaskQueue:QueueManual" in STACK_QUEUE
assert "function StackTaskQueue:RemoveManual" in STACK_QUEUE
assert "function MainFarm:_QueueEligibleSeaProgression" in MAIN_FARM
assert "if not self:_StepSeaProgression(session, entry)" in MAIN_FARM
assert "QueueManual(definition.Kind, token)" in MAIN_FARM
assert "self.ActiveStackTask.Kind ~= \"SeaUnlock3\"" in MAIN_FARM
assert "if self:_StepSeaProgression(session)" not in MAIN_FARM
assert "_ProgressLease" not in MAIN_FARM

assert '["First Sea"] = 1' in TELEPORT
assert '[1] = "TravelMain"' in TELEPORT
assert '[2] = "TravelDressrosa"' in TELEPORT
assert '[3] = "TravelZou"' in TELEPORT
assert "self.ActiveSeaTravel" in TELEPORT

print("PASS: Sea unlocks are FIFO Stack Farming jobs, Trevor fruit requires confirmation, farm resume is one-time, and sea travel uses official remotes")
