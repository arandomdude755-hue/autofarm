---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost puzzle, automatically use any currently ready skill; do not expose puzzle-only skill selection settings. Regular farming skill selection is separate and opt-in. Skull Guitar may be loaded and used against puzzle objects only if already owned; never buy items or server-hop for this feature. Farm Mastery follows the one current hotbar tool for its selected category, whether equipped or in Player.Backpack; do not search or load from the full stored inventory. This includes Skull Guitar as the Gun hotbar item. Use Skull Guitar TAP only when it is actually equipped. Resume the selected Farm Weapon after the puzzle phase.

The general “Use skills while farming” toggle gates only ordinary farm skill use. Farm Mastery uses the universal skill-key selections for its configured mastery category without requiring that toggle.

Farm Mastery uses the selected Farm Weapon to lower NPC health, then the configured Gun or Blox Fruit to finish at the health threshold. Mastery skills must keep using the shared regular farm skill selection, readiness, aim, input, and retry flow. Gun M1 may run independently alongside Gun skills, but only with the already-equipped Gun; do not force-equip Skull Guitar just for M1 or let M1 replace the skill path. Fruit M1 remains lower priority.

**Why:** the user wants Mastery to earn credit on the selected Gun or Blox Fruit by using it for the final damage after faster Farm Weapon damage. Ordinary farm skills already work; a separate Mastery execution path caused repeated stalls and wasted in-game testing. The user approved prioritizing Gun M1, and said the gun can M1 while skills are used.

**How to apply:** use the shared farm skill resolver and sender for both modes. Lock Mastery to its selected category below threshold, retain the general toggle and attack-position gate for ordinary skills, bypass that toggle and position gate for selected Mastery skills, and hold safely rather than finish with the wrong weapon while waiting. After equipping the hotbar tool, check its skill UI immediately if it has entered Character; wait only when the equip or matching UI is actually unavailable. Mastery movement may continue and retarget while a skill input is active; ordinary skill movement remains held steady during its key hold. Do not add separate key ordering or tool pinning.

**Why:** BNN equips the selected hotbar Tool and checks its Skills controls in the same pass. Returning unconditionally after EquipTool created an unnecessary preparing state even when the selected tool and ready controls had already synced.

**Why:** BNN Mastery attempts ready skills without an exact attack-position gate, while ordinary farm skills deliberately do not fire during travel. The old Mastery gate blocked before scanning when its new category position was 6.7 studs away (6-stud tolerance), and holding movement at a nearby stale goal could prevent reaching it.

**How to apply:** for Mastery, keep target/session/category/threshold checks and aim/input cleanup, but allow dispatch during approach and continue refreshing its movement goal. For ordinary farm skills, preserve the in-position check and pause movement retargeting while the skill is being sent. A held movement goal must enter the retarget branch when its destination changes, even if the new destination is within the normal near-goal threshold.

All farm skills, including travel skills, should aim at the current NPC through one shared target context. Refresh BNN-style outgoing-position aim from the current NPC throughout the eligible farm-skill target phase, then clear it when the target or skill-farming state changes. Match only the BNN one-argument Vector3/CFrame remote pattern. When ordinary farming and Farm Mastery are both enabled, Mastery takes priority at or below its health threshold and cancels an ordinary skill hold.

**Why:** the user tested BNN's aim behavior in-game and confirmed it works, and wants every skill aimed at the current target. BNN refreshes and retains its target position across the skill decision/target loop; a cast-only redirect can expire before delayed skill handling and fall back to the cursor. Mastery must deliver the last hit without competing with ordinary farm skills.

**How to apply:** route ordinary and Mastery skills through the shared refreshed target context while their existing eligibility rules pass; Tiki may use a cast-scoped context. Clear on target change, toggle-off, or stop. Keep Mastery's category/threshold rules separate from the general skill toggle, and stop an ordinary cast if the target crosses into Mastery range.

Use Vxeze's reference-style Gun M1 approach: locate the game's gun-shoot function by its identifying constants and target-lookup upvalue, then temporarily direct that lookup to the selected NPC. Do not manually fire Validator2 or ShootGunEvent remotes. Route Skull Guitar through the game's client gun-input path rather than assuming direct TAP RemoteEvent calls work. Keep M1 restricted to the already-equipped Gun, separate from skill dispatch, and report input/client firing-state evidence without claiming server damage. Fruit M1 remains lower priority. For skills on desktop and touch, use the reference-style VirtualInputManager key down/hold/up path; recognize both reference-ready cooldown bar sizes and do not require skill frames to be Visible.

**Why:** BNN and Quantum's manual validator/remote paths are version-sensitive, and Skull Guitar's direct TAP call did not work in the user's test even though manual TAP worked. Vxeze instead finds the client shoot function and overrides its target lookup, which is the approved implementation direction. The user clarified that the hotbar has exactly one tool per category and Mastery should follow that current item, including Skull Guitar, without loading from the full stored inventory.

**How to apply:** resolve mastery weapons only from live Character/Player.Backpack Tool instances; never query stored inventory. Prefer an equipped tool, otherwise use the one matching hotbar tool, including Skull Guitar. Keep the shared skill flow unchanged. Use the target-directed client gun handler only when a matching Gun is already equipped, restore its original target lookup immediately after firing, honor reload/cooldown state, and keep Gun M1 independently throttled from skills. Do not use direct TAP/Validator2/ShootGunEvent remote firing as a fallback.

Changing the target, Mastery method, or selected tool during a farm must not leave a stale skill input or preparation state blocking the current farm. Re-evaluate the active context and safely release/reset stale state when it changes.

**Why:** the user explicitly wants switching weapons or modes mid-farm to recover rather than break any farm function.

**How to apply:** track target/method/tool identity, cancel held input on context changes, clear cached readiness/preparation, then reacquire the current tool and skill UI before continuing.

For Gun M1 knockback, pause target-chasing briefly after the game reports a client firing-state change. Hold the player’s current position during that interval, then resume normal target tracking. Do not extend an active pause for every rapid shot, and do not change NPC physics or skill aiming.

**Why:** the user approved reducing chase jitter after Gun M1 because following each small knockback can push the player or NPC into walls.

**How to apply:** gate the pause on observed client firing state, scope it to the same target, keep it short and bounded, and clear it on target/method/tool changes or farm shutdown.
