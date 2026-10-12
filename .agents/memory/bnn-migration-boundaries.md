---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost event phase, configured skill use is allowed only during the puzzle. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Resume the selected Farm Weapon after the puzzle phase.

Do not port BNN's game-wide `__namecall` aim hook. Keep skill aiming temporary and target-scoped through the game's Mouse module, verify that the aim assignment works before sending a key, and release the key on cancellation.

**Why:** the user approved skill automation and owned Skull Guitar for the Tiki puzzle only, but did not approve purchases or server hopping. BNN also relies on executor-specific persistence and remote-interception APIs that are not portable or safely scoped.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI. Keep Tiki automation event-scoped, avoid global remote hooks, and resume normal farming equipment afterward.
