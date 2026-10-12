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
    "local trackedTarget = readTrackedQuestTarget(self, guideData, firstSea)", active_reader
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
    "titleContainsTarget(title, target, true)",
    "isVisibleGuiObjectWithin(titleLabel, trackedQuestFrame)",
    "isVisibleGuiObjectWithin(description, trackedQuestFrame)",
    "isVisibleGuiObjectWithin(progressLabel, trackedQuestFrame)",
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
    "local function normalizeQuestTargetName(name)",
    "local function trackedTargetMatches(catalogTarget, trackedTarget, allowFirstSeaVariants)",
    "trackedTargetMatches(mobName, targetName, true)",
    "firstSeaMatches[mobName] = true",
    'title:match("%((%d+)%s*/%s*(%d+)%)%s*$")',
):
    require(token in QUEST_SERVICE, f"safe progress/target mapping is missing: {token}")

require(
    "readTrackedQuestTarget(self, guideData, firstSea)" in QUEST_SERVICE,
    "First Sea-specific tracked-quest matching is not gated by sea detection",
)
require(
    "(allowFirstSeaActiveQuest or not excludedQuestNames[npcEntry.InternalQuestName])"
    in QUEST_SERVICE,
    "active First Sea tracking does not separate from quest-selection exclusions",
)
selector = QUEST_SERVICE[QUEST_SERVICE.index("function QuestService:SelectLevelQuest()"):]
require(
    "not excludedQuestNames[npcEntry.InternalQuestName]" in selector,
    "existing level-quest exclusions were removed",
)
for excluded_name in ("BartiloQuest", "Trainees", "MarineQuest", "CitizenQuest"):
    require(f"{excluded_name} = true" in QUEST_SERVICE,
            f"existing quest-selection exclusion changed: {excluded_name}")

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


def normalize_target_name(name):
    """Python fixture model of the bounded First Sea target normalization."""
    import re

    words = re.findall(r"[a-z0-9]+", name.lower())
    if not words:
        return None
    word = words[-1]
    if len(word) > 3 and word.endswith("ies") and word[-4] not in "aeiou":
        word = word[:-3] + "y"
    elif len(word) > 4 and word.endswith("es"):
        stem = word[:-2]
        if (stem.endswith(("s", "x", "z", "ch", "sh"))):
            word = stem
        elif len(word) > 2 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
            word = word[:-1]
    elif len(word) > 2 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
        word = word[:-1]
    words[-1] = word
    return " ".join(words)


def unique_first_sea_target(display_target, catalog_targets, progress_current, progress_total):
    """Fixture model: incomplete progress and one distinct catalog name are required."""
    if not isinstance(progress_current, int) or not isinstance(progress_total, int):
        return None
    if progress_total <= 0 or progress_current < 0 or progress_current >= progress_total:
        return None
    matches = {
        catalog_target
        for catalog_target, count in catalog_targets
        if isinstance(count, int)
        and count == progress_total
        and count > 1
        and normalize_target_name(catalog_target) == normalize_target_name(display_target)
    }
    return next(iter(matches)) if len(matches) == 1 else None


def parse_progress_text(text):
    import re

    match = re.fullmatch(r"\s*(\d+)\s*/\s*(\d+)\s*", text or "")
    if not match:
        return None
    current, total = (int(part) for part in match.groups())
    if total <= 0 or current >= total:
        return None
    return current, total


for display_target, candidates, expected in (
    ("Trainees", [("Trainee", 5)], "Trainee"),
    ("Bandits", [("Bandit", 5)], "Bandit"),
    ("Bandit", [("Bandit", 5)], "Bandit"),
    ("Trainees", [("Trainee", 5), ("Trainees", 5)], None),
    ("Trainees", [("Trainee", 4)], None),
):
    actual = unique_first_sea_target(display_target, candidates, 0, 5)
    require(actual == expected,
            f"unexpected First Sea target match for {display_target}: {actual!r}")
require(unique_first_sea_target("Trainees", [("Trainee", 5)], 5, 5) is None,
        "completed tracked quest progress must not map")
require(unique_first_sea_target("Trainees", [("Trainee", 5)], 6, 5) is None,
        "over-complete tracked quest progress must not map")
require(unique_first_sea_target("Trainees", [("Trainee", 5)], -1, 5) is None,
        "negative tracked quest progress must not map")
require(unique_first_sea_target("Trainees", [("Trainee", 5)], 0, 0) is None,
        "zero-total tracked quest progress must not map")
for invalid_progress in ("", "x/5", "0/0", "5/5", "6/5"):
    require(parse_progress_text(invalid_progress) is None,
            f"invalid or completed progress was accepted: {invalid_progress!r}")
require(parse_progress_text("0/5") == (0, 5),
        "valid incomplete tracked progress was rejected")
require(
    'if not allowFirstSeaVariants then\n        return false'
    in QUEST_SERVICE,
    "plural target normalization can affect non-First-Sea tracker matching",
)
print("PASS: tracker target fixtures cover singular/plural, ambiguity, count, and progress")

require("local ok, targetName = pcall(function()" in QUEST_SERVICE,
        "destroyed or absent UI reads are not protected")
require(
    'if firstSea then\n        local hudState, hudTarget, hudReason = readFirstSeaQuestHud(self, guideData)'
    in QUEST_SERVICE,
    "First Sea main-quest UI fallback is missing",
)

hud_start = QUEST_SERVICE.index("local function readFirstSeaQuestHud")
hud_end = QUEST_SERVICE.index("\nfunction QuestService.new", hud_start)
hud_reader = QUEST_SERVICE[hud_start:hud_end]
dialogue_start = QUEST_SERVICE.index("local function hasVisibleQuestGiverDialogue")
dialogue_end = QUEST_SERVICE.index("\nlocal function readFirstSeaQuestHud", dialogue_start)
dialogue_detector = QUEST_SERVICE[dialogue_start:dialogue_end]
quest_dialogue_match_start = QUEST_SERVICE.index(
    "local function matchesQuestDialogueTaskTitle"
)
quest_dialogue_match_end = QUEST_SERVICE.index(
    "\nlocal function hasVisibleQuestGiverDialogue",
    quest_dialogue_match_start,
)
quest_dialogue_matcher = QUEST_SERVICE[
    quest_dialogue_match_start:quest_dialogue_match_end
]
require(
    'playerGui:FindFirstChild("DialogueGui")' in dialogue_detector
    and 'FindFirstChild("dialogueTitleFrame", true)' in dialogue_detector
    and 'subtitle:FindFirstChild("title")' in dialogue_detector
    and 'speakerLabel = titleFrame:FindFirstChild("name")' in dialogue_detector
    and 'npcEntry.NPCName' in dialogue_detector
    and 'guideData.NPCList' in dialogue_detector
    and 'string.lower(titleText) == "rewards"' in dialogue_detector
    and 'matchesQuestDialogueTaskTitle(speakerText, quests)' in dialogue_detector
    and 'string.lower(titleText) == "quest giver"' in dialogue_detector,
    "dialogue detection must recognize the role title, catalog NPC name, or Rewards page",
)
require(
    'questData.Task' in quest_dialogue_matcher
    and 'local expectedTitle = "Defeat "' in quest_dialogue_matcher
    and 'normalizeQuestTargetName(expectedTitle) == normalizedTitle' in quest_dialogue_matcher,
    "the Rewards page must match its selected quest title against live quest-task data",
)
require(
    'if current:IsA("ScreenGui") and not current.Enabled then\n            return false'
    in QUEST_SERVICE,
    "effective GUI visibility must reject descendants of disabled ScreenGuis",
)

disabled_start = hud_reader.index("if main:IsA(\"ScreenGui\") and not main.Enabled then")
disabled_end = hud_reader.index('\n        local questFrame = main:FindFirstChild("Quest")', disabled_start)
disabled_branch = hud_reader[disabled_start:disabled_end]
require(
    'if hasVisibleQuestGiverDialogue(playerGui, guideData, self.Quests) then'
    in disabled_branch
    and 'return "none", nil,' in disabled_branch
    and 'StartQuest still requires active-state confirmation' in disabled_branch
    and 'no visible Quest Giver dialogue was found' in disabled_branch
    and 'main:FindFirstChild("Dialogue")' not in disabled_branch,
    "visible quest-giver dialogue must remain non-active and must not be mistaken for quest acceptance",
)
dialogue_gate_start = QUEST_SERVICE.index("function QuestService:IsQuestGiverDialogueOpen()")
dialogue_gate_end = QUEST_SERVICE.index("\nfunction QuestService:GetActiveQuestState()", dialogue_gate_start)
dialogue_gate = QUEST_SERVICE[dialogue_gate_start:dialogue_gate_end]
require(
    "hasVisibleQuestGiverDialogue" in dialogue_gate
    and "pcall(function()" in dialogue_gate
    and "return ok and isOpen == true" in dialogue_gate,
    "quest-start gating must safely reuse the visible generic quest-giver dialogue detector",
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
