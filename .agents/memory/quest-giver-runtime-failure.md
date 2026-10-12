---
name: Quest-giver runtime failure
description: Distinguishes the working First Sea target match from the separate dialogue-to-quest acceptance failure.
---

The user confirmed the first First Sea quest and its target matching work in-game. The separate failure occurs at a quest giver: the user taps to open the dialogue, but the quest does not start and the script does not detect it; the rest of farming works normally. Level 15 itself was not the cause.

The user now reports the spawn-target issue seems fixed. Keep spawn tracking out of the dialogue investigation unless the user reports it again. They also want redundant page/section/control subheadings removed and smaller function rows to leave room for more controls.

Live diagnostics showed `PlayerGui.Main` disabled and its `Dialogue` ImageLabel hidden. The actual open quest-giver UI is under `PlayerGui.DialogueGui`; its visible title reads `Quest Giver`. The user confirmed that quest requests work after this dialogue is accepted or closed, and that walking far enough away closes it. Manual acceptance still requires validated active-state evidence.

The user also observes different quest-status wording for the same situation across the three seas. Reports should identify the sea and preserve reader evidence so those differences can be compared.

**Why:** in-game diagnostics show that the old `Main.Dialogue` path is a hidden placeholder while a separate dialogue UI is visible. The second confirmation page changes its heading to `Rewards` and shows the selected task title (for example, `Defeat 8 Pirates`), so matching only `Quest Giver` or an NPC speaker misses it.

**How to apply:** keep quest acceptance, active-quest detection, and enemy/spawn discovery separate. Apply the same retreat/close/re-approach recovery to every quest-giver dialogue page. Recognize the generic role heading and confirmation pages whose `Rewards` heading is paired with a quest title derived from task count and target names in quest data; do not hardcode NPC or target names. Never infer acceptance from dialogue visibility or closure; retain validated acceptance checks. If a later page has a different structure, gather runtime evidence before broadening detection. Include sea and reader evidence in reports rather than normalizing away sea-specific paths. Avoid repeated section/control descriptions and keep the UI rows compact.
