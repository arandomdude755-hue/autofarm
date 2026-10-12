---
name: Quest-giver runtime failure
description: Distinguishes the working First Sea target match from the separate dialogue-to-quest acceptance failure.
---

The user confirmed the first First Sea quest and its target matching work in-game. The separate failure occurs at a quest giver: the user taps to open the dialogue, but the quest does not start and the script does not detect it; the rest of farming works normally. Level 15 itself was not the cause.

**Why:** the user corrected the earlier diagnosis using live-game behavior, and preserving the working quest-target path matters when addressing quest acceptance.

**How to apply:** keep quest acceptance, active-quest detection, and enemy/spawn discovery as separate paths. Do not regress the validated First Sea target matching to address the dialogue failure.
