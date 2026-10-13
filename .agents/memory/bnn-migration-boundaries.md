---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost puzzle, automatically use any currently ready skill; do not expose puzzle-only skill selection settings. Regular farming skill selection is separate and opt-in. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Farm Mastery may select a matching Gun or Blox Fruit tool from the Character or Player.Backpack; Player.Backpack means unequipped hotbar tools, not stored inventory. For Gun, prefer Skull Guitar if present in either live tool container. Equip and pin the exact selected tool for mastery attacks. Use Skull Guitar TAP only when that exact tool is equipped. Resume the selected Farm Weapon after the puzzle phase.

The general “Use skills while farming” toggle gates only ordinary farm skill use. Farm Mastery uses the universal skill-key selections for its configured mastery category without requiring that toggle.

For now, Farm Mastery is skills-only: do not send M1 after a skill, while selected skills cool down, or when skill controls are unavailable. Keep the configured Mastery weapon equipped and report why the farm is waiting.

**Why:** the user suspects M1 integration is causing Mastery failures and wants skills isolated first. If M1 is reconsidered, prioritize Gun; fruit M1 is lower priority because some fruits have no M1.

**How to apply:** preserve the normal skill-ready path and pin the selected tool. Every Mastery path that lacks a usable skill must remain handled without falling through to regular M1; expose cooldown, missing-UI, and activation-failure reasons in status.

Do not port BNN's game-wide `__namecall` aim hook. Keep skill aiming temporary and target-scoped through the game's Mouse module, verify that the aim assignment works before sending a key, and release the key on cancellation.

**Why:** the user sees no value in configuring skills used only for the Tiki puzzle and requested that it use any available skill automatically. They approved normal farming skill settings separately. The user did not approve purchases or server hopping. BNN also relies on executor-specific persistence and remote-interception APIs that are not portable or safely scoped.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI. Keep Tiki automation event-scoped and automatic, avoid global remote hooks, keep normal-farm skill controls independent, and resume the selected Farm Weapon after temporary equipment changes.

If Gun M1 is proposed again, first isolate it from skill dispatch and validate the reference-style target-aimed Gun input; do not manually fire validator or ShootGunEvent remotes. Fruit M1 remains lower priority. For skills on desktop and touch, use the reference-style VirtualInputManager key down/hold/up path; recognize both reference-ready cooldown bar sizes and do not require skill frames to be Visible.

**Why:** the user wants Gun M1 investigated separately after the skills-only Mastery path is stable, and considers fruit M1 lower priority. In-game testing showed `Tool:Activate()` could return successfully without firing a gun shot. The user clarified that Player.Backpack means unequipped hotbar tools rather than stored inventory, and explicitly asked to use Skull Guitar when present while choosing TAP only when it is the equipped gun.

**How to apply:** resolve mastery weapons only from live Character/Player.Backpack Tool instances, preferring Skull Guitar for Gun if present; do not query stored inventory. Reuse ordinary farm skill selection, equipping, key input, and aim behavior while pinning the selected mastery tool. Use TAP only when Skull Guitar itself is equipped. Any later regular-gun M1 must stay out of remotes/validator manipulation and be testable independently; report input sent—not confirmed damage—until live testing proves a hit.
