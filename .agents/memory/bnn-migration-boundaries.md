---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost puzzle, automatically use any currently ready skill; do not expose puzzle-only skill selection settings. Regular farming skill selection is separate and opt-in. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Farming and Farm Mastery must not auto-equip Skull Guitar from Backpack, but may use its Gun/TAP attack if the player already has it equipped. Resume the selected Farm Weapon after the puzzle phase.

The general “Use skills while farming” toggle gates only ordinary farm skill use. Farm Mastery uses the universal skill-key selections for its configured mastery category without requiring that toggle.

When no selected Mastery skill is ready or its controls fail to load, do not suppress all combat: keep the configured Mastery weapon equipped and use a throttled M1 fallback for that category.

**Why:** the user observed the farm idling at the Mastery health threshold while the player could manually change or unequip the weapon.

**How to apply:** preserve the normal skill-ready path, but ensure cooldown, missing-UI, and activation-failure paths still attack with the selected Mastery category and expose failures through status.

Do not label the M1 fallback's rate-limit window as "waiting for a ready skill." Preserve and report the last actual M1 result separately from skill readiness.

**Why:** the user saw a skill-readiness message that was actually caused by the M1 fallback throttle, hiding whether the gun was reloading or activation had merely been requested.

**How to apply:** when the fallback is rate-limited, report its prior result and the skill-key state distinctly; never treat Tool:Activate success as confirmation of damage.

Do not port BNN's game-wide `__namecall` aim hook. Keep skill aiming temporary and target-scoped through the game's Mouse module, verify that the aim assignment works before sending a key, and release the key on cancellation.

**Why:** the user sees no value in configuring skills used only for the Tiki puzzle and requested that it use any available skill automatically. They approved normal farming skill settings separately. The user did not approve purchases or server hopping. BNN also relies on executor-specific persistence and remote-interception APIs that are not portable or safely scoped.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI. Keep Tiki automation event-scoped and automatic, avoid global remote hooks, keep normal-farm skill controls independent, and resume the selected Farm Weapon after temporary equipment changes.

For Gun Mastery, use the validated CombatController `shootGun` input path with target screen coordinates; keep the optional internal-function lookup in Compatibility and do not manually fire validator or ShootGunEvent remotes. For skills on desktop and touch, use the reference-style VirtualInputManager key down/hold/up path; recognize both reference-ready cooldown bar sizes and do not require skill frames to be Visible.

**Why:** in-game testing showed `Tool:Activate()` could return successfully without firing a gun shot. The references use the game's internal shooting input handler and accept both empty-width and full-width cooldown states without checking frame visibility. The user clarified that Skull Guitar must not be auto-equipped for mastery, but should still work if already equipped.

**How to apply:** do not auto-equip Skull Guitar from Backpack for farming/mastery; when already equipped, allow the reference TAP attack path. For regular guns, only invoke an upvalue after validating it is the named `shootGun` function. Synthesize target screen input and retain range/reload/cooldown checks. Report input sent—not confirmed damage—until live testing proves a hit.
