# Cue artwork

The Cue Workshop ships fifteen RGBA PNG sprites in `mod/assets/cues/`. They are original generated artwork made with the built-in imagegen tool, then exported as individual full-length cue sprites. Native game artwork is reused by reference at runtime and is not redistributed.

## Production specification

The cues use the game's illustrated tavern direction: dark ink outlines, warm flat cel shading, carved wood, readable wrapped grips, and small inlays. All source cues point left; the native sprite integration flips them to match the game's right-facing cue. House retains the original native in-game sprite and uses its generated sprite in the shop.

Images are decoded once at controller startup and reused by the shop and aiming visuals. Fifteen exported PNGs total approximately 3.83 MB compressed. Their dimensions vary from 1476–1515 by 74–103 pixels. Exports trim atlas row margins, retain generated color/alpha, and zero alpha values at or below 8 to remove imperceptible matte noise. No generated background is used as part of the native shop.

## Final prompt set

The common prompt for the final four three-cue sheets was:

> Use case: stylized-concept. Production 2D game sprite atlas: exactly THREE separate full-length straight billiard cue sticks in three evenly spaced horizontal rows. Tip LEFT, butt RIGHT. Transparent alpha background. Each cue has same endpoints and generous empty space, no other objects, NO cast shadows, NO glow, NO lighting halos, no background colors, no rack, no text. Hand-drawn indie pool tavern style: dark ink outline, warm flat cel shading, two or three tones, readable small, attractive carved shafts and distinctive wrapped grips. Wide 1536x1024 sprite sheet.

Each sheet appended one of these design specifications:

1. **Bankshot / Double Rail / Carom:** Top Bankshot: rich walnut, emerald leather wrap, brass single-chevron inlays. Middle Double Rail: black ebony with copper grip, twin parallel brass bands and two tiny chevrons. Bottom Carom: blond maple with navy grip, ivory interlocking diamond inlays.
2. **Silk / Thunder / Opener:** Top Silk: pale ivory shaft, dusty rose silk wrap, subtle silver filigree. Middle Thunder: charcoal ash shaft, deep violet grip with thin gold lightning-bolt inlays. Bottom Opener: honey wood, burnt orange grip with a small brass rising-sun motif.
3. **Closer / Comeback / Relay:** Top Closer: dark walnut, forest green grip and ivory three-dot inlay. Middle Comeback: warm auburn wood, red leather grip and cream upward phoenix-feather inlay. Bottom Relay: light maple, alternating teal and coral grip segments, interlocking brass link motif.
4. **Corner / Sidewinder / Clean:** Top Corner: warm oak shaft, burgundy grip, ivory right-angle corner inlays. Middle Sidewinder: olivewood shaft, jade green grip with subtle flowing brass wave inlay. Bottom Clean: bleached ash shaft, chalk-white linen grip with restrained black pinstripes and silver ferrule.

The House / Finesse / Firm source prompt was:

> Use case: stylized-concept. Asset type: production 2D game sprite atlas, transparent background. Create ONE sprite sheet containing EXACTLY THREE separate full-length billiard cue sticks, each perfectly horizontal, evenly separated in three rows, generous empty transparent margins, tip points LEFT and butt RIGHT. House cue top: honey maple wood, black wrap, ivory ferrule. Finesse cue middle: slim pale ash shaft, muted teal wrap and small brass diamond inlays. Firm cue bottom: warm chestnut shaft, burgundy grip and simple brass bands. Style: hand-drawn 2D indie pool tavern game, bold dark brown ink outlines, warm flat cel shading with only two or three tones, slightly playful chunky proportions, clear silhouettes readable at 300 by 20 pixels, subtle hand-painted wood grain, no photographic rendering. Each cue straight and aligned at identical endpoints, no racks, supports, shadows outside silhouette, labels, text, lettering, symbols, perspective or scenery. Transparent background with actual alpha, NOT checkerboard. Landscape wide sprite sheet, 1536x1024. Separate rows allow lossless extraction for game assets.

Its final background-extraction edit prompt was:

> Use case: background-extraction. Edit this three-cue sprite sheet. Remove ALL black background, colored glow, atmosphere and shadows around cues. Replace with actual transparent alpha everywhere except the three cue sticks. Keep all three cue stick designs, straight shapes, full-length horizontal orientations tip left, equal endpoints, materials, colors, outline, and row spacing exactly unchanged. No new background, no checkerboard, no rack, no text. Pure transparent production game sprite atlas with clean hard silhouette edges.
