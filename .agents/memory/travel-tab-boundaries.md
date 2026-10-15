---
name: Travel tab boundaries
description: User-approved scope for manual island and NPC travel.
---

Island and NPC travel are user-controlled toggles that turn off automatically on arrival; do not show a separate Cancel travel control. Offer only destinations in the current sea; the player changes seas manually. Do not add automatic sea travel or server hopping. Manual Travel-tab trips and Auto Farm must not move the character at the same time; gateway routing inside an active farm is part of that farm's own movement. NPC lookup should include live Workspace NPCs and valid current-sea ReplicatedStorage templates. For remote map gateways, approach the route's activation stand, retry bounded `requestEntrance` calls while confirming arrival by position, and do not treat a returned `nil` as success.

All long-distance travel initiated by farm modes or other tasks should use the same gateway planner and route executor as the Travel tab whenever a route is meaningfully shorter; otherwise retain normal movement as the fallback.

Gateway failures should not suppress a route for an extended period: use a 10-second cooldown after activation failure, an 8-second cooldown after failing to reach the pad, and retain the previous failure details for the next diagnostic. An approach failure is not proof that the gateway activation is broken.

The user reports that defeating Tyrant of the Skies grants Tiki portal access, Feathered Visage is not guaranteed, and the “Liberator of the Sky” title is guaranteed. The title list is populated only while TitlesMenu is open; a missing entry while closed means unknown, not locked. For Tiki gateways, check Feathered Visage first, then use the title menu’s explicit unlocked/locked marker; a bounded hidden UI probe is preferred over a blind remote call. Only probe title access when that gateway can materially shorten the current trip; if the list is still loading, keep the bounded background check pending during the first safe route leg rather than treating an early timeout as a denial. Confirm access before activating a title-gated gateway; if access remains unknown at that point, skip that route for the current trip.

Cache a confirmed absence of both Feathered Visage and the Tiki access title per account so future routes do not reopen the title menu repeatedly. Unknown or failed checks are not negative evidence; recheck inventory before honoring the cached result, and let the cache refresh so a title earned later can be recognized.

**Why:** the user wants confirmed no-access results reused rather than repeating the Tiki title probe on every travel attempt.

**How to apply:** cache only when the inventory scan definitively reports no Feathered Visage and the title row explicitly reports locked; clear the negative cache when the item is found, and keep the cache bounded for later title unlocks.

**Why:** the user explicitly requested BNN-style travel toggles with automatic shutoff, broader NPC discovery, manual sea changes, no server hopping, no movement conflict with Auto Farm, and shared shortest-gateway routing for all travel tasks. They also confirmed remote activation alone no longer works and that the Vxeze-style approach is appropriate. The Tiki access and reward details are user-provided; runtime scans show the title entry disappears when TitlesMenu is closed, and the reference scripts only open the menu rather than verify title ownership. The user approved checking the title only after the item check and minimizing the menu probe’s visibility. A recent in-game report showed title ownership can be true while the touch trigger is absent because the character is far from that streamed map region. Title probing has a real UI-load cost, so skip it when the route cannot beat normal travel. The Farm Materials report also showed that two needed routes remained disabled for nearly two minutes after earlier failures, while replanning had erased the activation details. A later in-game report showed the title UI had not populated within a subsecond probe even though the title row was available afterward. The user approved overlapping the first travel leg with title verification to reduce the no-Feathered-Visage delay, while retaining the ownership gate.

**How to apply:** keep destination lists current-sea-filtered, reject travel while Auto Farm is active, turn off the active travel toggle when movement ends or is cancelled, and stop travel before Auto Farm starts. For every gateway type, finish movement at the configured stand, stabilize the character before activation, use a bounded retry window, and confirm a real position transition near the destination before replanning. Internal movement cleanup during a route leg must stop only the movement session, not cancel the owning farm-travel request. For touch-only routes, a streamed-out trigger is not an ownership failure: keep the route eligible when access and touch support are confirmed, then resolve the exact tagged trigger after reaching the stand. Treat a missing title entry while the menu is closed as unknown; check Feathered Visage first, then briefly probe TitlesMenu with its original visibility restored, and skip the Tiki route if title state remains unknown. Cool down activation failures for 10 seconds and pad-approach failures for 8 seconds; include prior failure details in subsequent route diagnostics. Begin title checks before or during the earliest safe route leg, stop an approach when confirmed access is denied, and recheck immediately before touch activation.

For farm targets in Submerged, plan map gateways toward Tiki staging first, then use the Submarine Worker transport and confirm arrival in Submerged before continuing to the actual target.

**Why:** Submerged is entered through the Tiki NPC transport, so comparing map gateways against the underwater target as if it were a normal island endpoint can hide a much shorter composite route.

**How to apply:** keep map-gateway planning aimed at the Tiki staging point for outbound Submerged trips; retain the existing MovementService route as fallback when no shorter gateway plan is available.

For travel starting inside Submerged and heading elsewhere, first use the Submerged exit transport to Tiki Outpost, confirm arrival, then plan map gateways from Tiki to the final destination. This applies to both farm travel and manual Travel-tab trips.

**Why:** map gateways are outside Submerged; scoring them from the underwater starting position can choose a poor route or skip the necessary Submarine Transportation step.

**How to apply:** move to the existing submerged exit staging point, use the shared MovementService route request, verify arrival near Tiki Outpost, and only then compute gateway legs to the destination.
