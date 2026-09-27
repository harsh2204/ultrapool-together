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


## Rook and the equipped cue case

The cue counter uses a four-cel Rook atlas (`mod/assets/cues/shop/rook_states.png`) and an empty felt-lined case (`cue_equipped_case.png`). Both were generated with the built-in imagegen tool from the approved shop concept. They use real alpha; source PNGs are retained without raster editing. Native backgrounds, counter sections, arrow art and fonts remain referenced from the installed game.

Rook's 1086 × 1448 atlas has four 543 × 724 cells: resting, blink, talking, and talking while blinking. The body pose and registration stay consistent. Native-style idle movement, occasional blink, short speech and click nudge animate the retained sprite only while the cue counter is active. The case is 1024 × 1536. Fixed atlas regions omit transparent padding and imperceptible alpha fringe; the player cue is drawn live in the felt compartment, using the confirmed model and finish rather than the browsing preview. Two immutable textures add approximately 2.82 MiB compressed before packaging.

### Rook generation prompt

```
Use case: background-extraction / production sprite atlas.
Using the approved reference image, extract and faithfully reproduce ONLY ROOK, the white-haired horned demon cue seller. Create a game-ready transparent PNG sprite sheet with FOUR identically registered waist-up character frames in an exact 2-column by 2-row grid. Canvas 1536x2048, each cell exactly768x1024. Actual transparent alpha background everywhere outside character, no checkerboard, no scenery, counter, UI, labels, nameplate, lights, other characters, or shadows outside the silhouette.
All FOUR frames show EXACTLY the same original Rook identity, proportions, clothes, hair, horns, pose and held cue/cloth from the approved screen: warm ochre skin, swept ivory hair, two dark curved horns, pointed ears, amber eyes, brass hoop earring, burgundy rolled-sleeve shirt, olive apron/brass clasps, holding a green-wrapped wood cue diagonally up to the right with a cream polishing cloth. Hands anatomically clear and natural. Preserve dark thick ink outlines, flat warm cel shading and the game's expressive illustrated style, no realistic rendering. Frame him from horn tops through both complete forearms to a straight horizontal waist cut. Full silhouette and cue remain inside every cell with generous 32-pixel clear margins. IDENTICAL scale, silhouette placement, eye positions, head angle and waist baseline in all cells; each is a registered animation cel, not four different poses. Body and hands do not change at all.
TOP LEFT: resting half-smile, eyes open, mouth closed.
TOP RIGHT: same resting frame, BOTH eyes naturally shut for one blink, mouth closed.
BOTTOM LEFT: same frame, eyes open, mouth slightly open mid-speech.
BOTTOM RIGHT: same frame, eyes shut and mouth slightly open mid-speech.
Only eyes and mouth change between cells. Everything else is identical. No lettering of any kind. Crisp production sprite edges, fully transparent background.
```

### Rook spacing refinement

```
Edit this production Rook 2x2 four-state transparent sprite sheet ONLY to fix frame spacing/registration. Keep this exact character design, palette, ink lines, pose, hand/cue/cloth, facial expressions and four-state order (top-left idle, top-right blink, bottom-left talking, bottom-right talking+blink). Shrink EACH complete character uniformly to 84% of its current size within its own quadrant and center it within that quadrant. Ensure every horn, elbow, hair strand and full cue tip is INSIDE its cell with at least 30 transparent pixels of margin on all four sides. Exact equal quadrant cells, equal scale and identical pose registration, head and waist same relative pixel locations in every cell. No part may cross a horizontal or vertical midpoint. Do NOT crop any cue, hand or elbow. ONLY eyes/mouth differ. Maintain fully transparent alpha everywhere outside hard-edged opaque characters. Remove stray colored edge pixels. No text, no background, no cast shadow or glow. Keep canvas a 2:2 grid whose width and height are divisible by 2.
```

### Empty case generation prompt

```
Use case: stylized-concept.
Asset type: one transparent game UI prop sprite, an EMPTY upright cue display case for the approved Ultrapool cue-shop screen.
Use the attached game mockup strictly for art style: dark chunky ink outlines, warm two/three-tone flat cel shading, simple bold readable materials. Create one tall open FRONT-FACING wooden cue case, around 2:3 overall width:height, facing the viewer without perspective foreshortening. Warm dark walnut border, small restrained brass corner guards and hinges, deep desaturated green felt interior, two small leather keeper straps at upper/lower thirds. A slim open lid visible just to the left, main deep empty felt compartment occupies the central/right two-thirds. The case will sit below/right of the counter next to the native inventory and hold ONE upright player cue composited in code.
No cue in the case. No labels, text, letters, symbols, price, hands, character, scenery, floor or outside cast shadow. The entire center must remain clear continuous felt with no extra dividers or decoration, suitable for overlaying a tall thin cue. Small blank cream/brass nameplate on lower frame may be included. Exact transparent alpha outside the case silhouette; no white/black/checkerboard background. Modest prop detailing, not photorealistic, painterly, shiny luxury product or 3D render. Portrait canvas 1024x1536 with comfortable transparent margins.
```

### Empty case transparency refinement

```
Use case: background-extraction. Edit this cue-case image. Keep the exact wooden case, hinges, brass, green felt and straps design and shape unchanged. Remove ALL surrounding black background, brown/yellow haze, glow, shadow and atmosphere; replace absolutely everything outside the crisp case silhouette with actual transparent alpha. Make the case itself fully opaque. There must be no glow halos, translucent cloud, black rectangle, drop shadow or checkerboard. Do not add text or a cue. A clean production PNG prop sprite cutout.
```
