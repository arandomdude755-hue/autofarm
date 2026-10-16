---
name: Team-selection confirmation
description: Reliable startup team selection in Blox Fruits when the client may already expose a Team before the chooser closes.
---

Do not treat `Player.Team ~= nil` alone as proof that startup team selection is finished. The chooser can still be open; success requires an assigned team and a closed/missing `ChooseTeam` prompt. BNN also invokes `CommF_:InvokeServer("SetTeam", teamName)`, while Vxeze retries the selected UI button until the chooser is dismissed.

**Why:** An early return on an already-populated `Player.Team` left the join screen open and made auto-selection appear broken.

**How to apply:** For future startup selection changes, validate both the team property and chooser state; keep the source-backed `SetTeam` request and UI-input retry as bounded paths.
