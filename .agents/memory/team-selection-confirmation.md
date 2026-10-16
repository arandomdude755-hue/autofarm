---
name: Team-selection confirmation
description: Reliable startup team selection in Blox Fruits when the client may already expose a Team before the chooser closes.
---

Do not treat `Player.Team ~= nil` alone as proof that startup team selection is finished. The chooser can still be open; success requires an assigned team and a closed/missing `ChooseTeam` prompt. For mobile-safe startup selection, activate the chooser button directly (`Activated` signal when supported, otherwise `GuiButton:Activate()`); avoid selecting GUI focus or simulating keyboard input.

**Why:** Keyboard-based selection switched mobile players to computer controls and left a visible focus outline. The supplied BloxFruits source fires `Activated`, while BNN/Vxeze use a keyboard Return key.

**How to apply:** Retry direct button activation at a bounded interval, then verify both the team property and that the chooser closed. Do not add a `SetTeam` remote or virtual keyboard path to startup selection.
