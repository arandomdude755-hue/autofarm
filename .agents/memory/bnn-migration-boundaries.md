---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost puzzle, automatically use any currently ready skill; do not expose puzzle-only skill selection settings. Regular farming skill selection is separate and opt-in. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Resume the selected Farm Weapon after the puzzle phase.

The general “Use skills while farming” toggle gates only ordinary farm skill use. Farm Mastery uses the universal skill-key selections for its configured mastery category without requiring that toggle.

Do not port BNN's game-wide `__namecall` aim hook. Keep skill aiming temporary and target-scoped through the game's Mouse module, verify that the aim assignment works before sending a key, and release the key on cancellation.

**Why:** the user sees no value in configuring skills used only for the Tiki puzzle and requested that it use any available skill automatically. They approved normal farming skill settings separately. The user did not approve purchases or server hopping. BNN also relies on executor-specific persistence and remote-interception APIs that are not portable or safely scoped.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI. Keep Tiki automation event-scoped and automatic, avoid global remote hooks, keep normal-farm skill controls independent, and resume the selected Farm Weapon after temporary equipment changes.

For Gun Mastery, use the standard equipped Tool activation path with temporary target-scoped Mouse aim. Do not send the BNN validator or ShootGunEvent requests.

**Why:** the user tested the BNN-style gun M1 path and reported that it did not work, then requested the original Tool activation approach.

**How to apply:** keep this path limited to the Gun Mastery phase after the character reaches attack position; retain range/reload/cooldown checks and selected skill usage, and label success as an issued activation until in-game damage is confirmed.
