#!/usr/bin/env python3
"""Static regression checks for the tracked-quest state fallback."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QUEST_SERVICE = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/Farm/QuestService.lua"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


active_reader = QUEST_SERVICE.index("function QuestService:GetActiveQuestState()")
preferred_read = QUEST_SERVICE.index("return \"active\", targetName", active_reader)
fallback_read = QUEST_SERVICE.index(
    "local trackedTarget = readTrackedQuestTarget(self, guideData)", active_reader
)
require(preferred_read < fallback_read, "GuideModule QuestData is no longer preferred")
require(
    'return "active", trackedTarget' in QUEST_SERVICE,
    "tracked UI target is not returned through the existing active-state contract",
)

for token in (
    'FindFirstChild("TrackedQuestFrame")',
    'trackedQuestFrame:IsA("ScreenGui")',
    "trackedQuestFrame.Enabled",
    'FindFirstChild("Frame")',
    'FindFirstChild("header")',
    'FindFirstChild("textLabel")',
    'FindFirstChild("description")',
    'FindFirstChild("progress")',
    "titleLabel.Text",
    "description.Text",
    "progressLabel.Text",
):
    require(token in QUEST_SERVICE, f"tracked quest UI validation is missing: {token}")

for token in (
    '"^%s*(%d+)%s*/%s*(%d+)%s*$"',
    "MAX_TRACKED_QUEST_PROGRESS_LENGTH",
    "total <= 0",
    "current > total",
    "numericLevel <= level",
    "self.Quests[npcEntry.InternalQuestName]",
    "type(quest.Task) == \"table\"",
    "local mobName, count = next(quest.Task)",
    "numericCount == progressTotal",
    "numericCount > 1",
):
    require(token in QUEST_SERVICE, f"safe progress/target mapping is missing: {token}")

require("local ok, targetName = pcall(function()" in QUEST_SERVICE,
        "destroyed or absent UI reads are not protected")
require(
    'if questData == nil then\n        return "none", nil' in QUEST_SERVICE,
    "unmapped missing quest data no longer preserves existing no-target behavior",
)

print("PASS: GuideModule remains preferred; tracked UI requires validated and catalog-mapped state")
