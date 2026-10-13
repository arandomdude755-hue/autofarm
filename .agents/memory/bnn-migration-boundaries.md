---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost puzzle, automatically use any currently ready skill; do not expose puzzle-only skill selection settings. Regular farming skill selection is separate and opt-in. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Farm Mastery may select a matching Gun or Blox Fruit tool from the Character or Player.Backpack; Player.Backpack means unequipped hotbar tools, not stored inventory. For Gun, prefer Skull Guitar if present in either live tool container. Use Skull Guitar TAP only when it is actually equipped. Resume the selected Farm Weapon after the puzzle phase.

The general “Use skills while farming” toggle gates only ordinary farm skill use. Farm Mastery uses the universal skill-key selections for its configured mastery category without requiring that toggle.

For now, Farm Mastery is skills-only: the selected Farm Weapon lowers NPC health; at or below the configured threshold, the selected Gun or Blox Fruit skills should deliver the finishing damage. Do not send M1 with the wrong weapon while selected mastery skills cool down or their controls are unavailable. Mastery must use the regular farm skill selection, weapon resolution, cooldown/readiness, aim, input, and retry flow, with only the threshold/category policy and bypass of the general Use Skills While Farming toggle differing. Do not add Mastery-only tool pinning or key rotation.

**Why:** the user wants Mastery to earn credit on the selected Gun or Blox Fruit by using it for the final damage after faster Farm Weapon damage. Ordinary farm skills already work; a separate Mastery execution path caused repeated stalls and wasted in-game testing. If M1 is reconsidered, prioritize Gun; fruit M1 is lower priority because some fruits have no M1.

**How to apply:** use the shared farm skill resolver and sender for both modes. Lock Mastery to its selected category below threshold, retain the general toggle and attack-position gate for ordinary skills, bypass that toggle and position gate for selected Mastery skills, and hold safely rather than finish with the wrong weapon while waiting. Mastery movement may continue and retarget while a skill input is active; ordinary skill movement remains held steady during its key hold. Do not add separate key ordering or tool pinning.

**Why:** BNN Mastery attempts ready skills without an exact attack-position gate, while ordinary farm skills deliberately do not fire during travel. The old Mastery gate blocked before scanning when its new category position was 6.7 studs away (6-stud tolerance), and holding movement at a nearby stale goal could prevent reaching it.

**How to apply:** for Mastery, keep target/session/category/threshold checks and aim/input cleanup, but allow dispatch during approach and continue refreshing its movement goal. For ordinary farm skills, preserve the in-position check and pause movement retargeting while the skill is being sent. A held movement goal must enter the retarget branch when its destination changes, even if the new destination is within the normal near-goal threshold.

All farm skills, including travel skills, should aim at the current NPC through one shared target context. Refresh BNN-style outgoing-position aim from the current NPC throughout the eligible farm-skill target phase, then clear it when the target or skill-farming state changes. Match only the BNN one-argument Vector3/CFrame remote pattern. When ordinary farming and Farm Mastery are both enabled, Mastery takes priority at or below its health threshold and cancels an ordinary skill hold.

**Why:** the user tested BNN's aim behavior in-game and confirmed it works, and wants every skill aimed at the current target. BNN refreshes and retains its target position across the skill decision/target loop; a cast-only redirect can expire before delayed skill handling and fall back to the cursor. Mastery must deliver the last hit without competing with ordinary farm skills.

**How to apply:** route ordinary and Mastery skills through the shared refreshed target context while their existing eligibility rules pass; Tiki may use a cast-scoped context. Clear on target change, toggle-off, or stop. Keep Mastery's category/threshold rules separate from the general skill toggle, and stop an ordinary cast if the target crosses into Mastery range.

If Gun M1 is proposed again, first isolate it from skill dispatch and validate the reference-style target-aimed Gun input; do not manually fire validator or ShootGunEvent remotes. Fruit M1 remains lower priority. For skills on desktop and touch, use the reference-style VirtualInputManager key down/hold/up path; recognize both reference-ready cooldown bar sizes and do not require skill frames to be Visible.

**Why:** the user wants Gun M1 investigated separately after the skills-only Mastery path is stable, and considers fruit M1 lower priority. In-game testing showed `Tool:Activate()` could return successfully without firing a gun shot. The user clarified that Player.Backpack means unequipped hotbar tools rather than stored inventory, and explicitly asked to use Skull Guitar when present while choosing TAP only when it is the equipped gun.

**How to apply:** resolve mastery weapons only from live Character/Player.Backpack Tool instances, preferring Skull Guitar for Gun if present; do not query stored inventory. Reuse the ordinary farm skill selection, equip, key input, and aim flow without Mastery-only tool pinning. Use TAP only when Skull Guitar itself is equipped. Any later regular-gun M1 must stay out of remotes/validator manipulation and be testable independently; report input sent—not confirmed damage—until live testing proves a hit.
