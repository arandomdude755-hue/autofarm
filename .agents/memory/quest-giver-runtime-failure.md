---
name: Quest-giver runtime failure
description: Distinguishes the working First Sea target match from the separate dialogue-to-quest acceptance failure.
---

The user confirmed the first First Sea quest and its target matching work in-game. The separate failure occurs at a quest giver: the user taps to open the dialogue, but the quest does not start and the script does not detect it; the rest of farming works normally. Level 15 itself was not the cause.

The user now reports the spawn-target issue seems fixed. Keep spawn tracking out of the dialogue investigation unless the user reports it again. They also want redundant page/section/control subheadings removed and smaller function rows to leave room for more controls.

When the quest-giver dialogue is open, the user's runtime reports `PlayerGui.Main ScreenGui is disabled`. A visible `Main.Dialogue` may justify attempting the bounded quest request, but never counts as quest acceptance; confirmation still requires validated quest state. A disabled Main without visible dialogue remains unknown.

**Why:** the user corrected the earlier diagnosis using live-game behavior and clarified the current scope and UI direction; preserving the working quest-target path matters when addressing quest acceptance.

**How to apply:** keep quest acceptance, active-quest detection, and enemy/spawn discovery as separate paths. Do not regress the validated First Sea target matching or reopen spawn discovery for the dialogue failure. Avoid repeated section/control descriptions and keep the UI rows compact. Only allow the explicit visible-dialogue request path; retain validated acceptance checks.
