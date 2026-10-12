---
name: Quest-giver runtime failure
description: Distinguishes the working First Sea target match from the separate dialogue-to-quest acceptance failure.
---

The user confirmed the first First Sea quest and its target matching work in-game. The separate failure occurs at a quest giver: the user taps to open the dialogue, but the quest does not start and the script does not detect it; the rest of farming works normally. Level 15 itself was not the cause.

The user now reports the spawn-target issue seems fixed. Keep spawn tracking out of the dialogue investigation unless the user reports it again. They also want redundant page/section/control subheadings removed and smaller function rows to leave room for more controls.

Live diagnostics showed `PlayerGui.Main` disabled and its `Dialogue` ImageLabel hidden. The actual open quest-giver UI is under `PlayerGui.DialogueGui`; its visible title reads `Quest Giver`. Use that generic title as a request opportunity, never as proof of acceptance.

**Why:** the user's in-game diagnostic proved the older `Main.Dialogue` path is a hidden placeholder while a separate dialogue UI is visible.

**How to apply:** keep quest acceptance, active-quest detection, and enemy/spawn discovery as separate paths. Do not regress the validated First Sea target matching or reopen spawn discovery for the dialogue failure. Use the visible `DialogueGui` quest-giver title only to permit a bounded request; retain validated acceptance checks. Avoid repeated section/control descriptions and keep the UI rows compact.
