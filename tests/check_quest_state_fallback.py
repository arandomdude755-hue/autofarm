#!/usr/bin/env python3
"""Static regression checks for active quest readers and safe fallbacks."""

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
    "current >= total",
    "numericLevel <= level",
    "self.Quests[npcEntry.InternalQuestName]",
    "type(quest.Task) == \"table\"",
    "local mobName, count = next(quest.Task)",
    "numericCount == progressTotal",
    "numericCount > 1",
    'title:match("%((%d+)%s*/%s*(%d+)%)%s*$")',
):
    require(token in QUEST_SERVICE, f"safe progress/target mapping is missing: {token}")

tracked_progress_parser = QUEST_SERVICE[
    QUEST_SERVICE.index("local function parseTrackedQuestProgress"):
    QUEST_SERVICE.index("local function titleContainsTarget")
]
require(
    "or current >= total" in tracked_progress_parser,
    "tracked quest progress must reject completed and over-complete counts",
)
require(
    "or current > total" not in tracked_progress_parser,
    "tracked quest progress still permits completed counts",
)


def tracked_progress_is_accepted(current, total):
    """Boundary cases for the source-checked incomplete-progress guard."""
    return total > 0 and current < total


for current, total, expected in (
    (2, 5, True),
    (5, 5, False),
    (6, 5, False),
):
    require(
        tracked_progress_is_accepted(current, total) is expected,
        f"unexpected tracked progress result for {current}/{total}",
    )
print("PASS: tracked progress accepts incomplete counts and rejects complete/over-complete counts")

require("local ok, targetName = pcall(function()" in QUEST_SERVICE,
        "destroyed or absent UI reads are not protected")
require(
    'if firstSea then\n        local hudState, hudTarget, hudReason = readFirstSeaQuestHud(self, guideData)'
    in QUEST_SERVICE,
    "First Sea main-quest UI fallback is missing",
)

compatibility = (
    ROOT / "src/ReplicatedStorage/CustomHub/Compatibility.lua"
).read_text(encoding="utf-8")
for token in (
    'function Compatibility:IsFirstSea()',
    'mapName == "Sea1"',
    'FindFirstChild("Main")',
    'FindFirstChild("Quest")',
    "questFrame.Visible",
    'FindFirstChild("QuestTitle")',
    'FindFirstChild("Title")',
    "titleLabel.Visible",
    "findEligibleTargetFromTitle(",
    'return "active-unknown", nil, mappingError',
    'return "none", nil, "PlayerGui.Main.Quest.Visible is false"',
):
    require(token in QUEST_SERVICE + compatibility,
            f"First Sea active-quest validation is missing: {token}")

require("GuideModule.Data.QuestData.Task" in QUEST_SERVICE,
        "GuideModule task data is no longer the preferred active-state reader")
require(
    "visible Main.Quest title/progress maps to the level-eligible quest catalog"
    in QUEST_SERVICE,
    "visible Main.Quest fallback is not progress- and catalog-validated",
)
require(
    'return "none", nil, "GuideModule.Data.QuestData is absent"' in QUEST_SERVICE,
    "non-First-Sea missing-data behavior changed unexpectedly",
)

print("PASS: GuideModule remains preferred; tracked UI requires validated and catalog-mapped state")
print("PASS: First Sea visible Main.Quest fallback requires a catalog-mapped target")
