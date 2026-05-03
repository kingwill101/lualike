# Relic Breach Asset Manifest

This example starts with a code-only prototype shell so runtime work can begin
before external art is downloaded. The target art/audio set is intentionally
biased toward one primary source so the style and license story stay simple.

## Primary Source

- Provider: `Kenney`
- License basis: <https://kenney.nl/support>
- Verified support statement:
  - Kenney states that all game assets on the asset pages are public-domain
    licensed `CC0`.
  - Kenney also states that attribution is not required.

## Packs To Use

### Core visual pack

- Pack: `Roguelike/RPG Pack`
- URL: <https://kenney.nl/assets/roguelike-rpg-pack>
- Local destination: `art/kenney_roguelike_rpg_pack/`
- Use for:
  - dungeon floor and wall tiles
  - props, braziers, doors, traps, barrels, crates
  - pickups and environmental objects

### Character pack

- Pack: `Roguelike Characters`
- URL: <https://kenney.nl/assets/roguelike-characters>
- Local destination: `art/kenney_roguelike_characters/`
- Use for:
  - player sprite
  - enemy sprite candidates
  - NPC variants and future character swaps

### UI pack

- Pack: `UI Pack - Pixel Adventure`
- URL: <https://kenney.nl/assets/ui-pack-pixel-adventure>
- Local destination: `art/kenney_ui_pack_pixel_adventure/`
- Use for:
  - HUD frames
  - buttons and menu chrome
  - health and ammo widgets
  - popups, tabs, and pause menu surfaces

### Input prompt pack

- Pack: `Input Prompts Pixel`
- URL: <https://kenney.nl/assets/input-prompts-pixel>
- Local destination: `art/kenney_input_prompts_pixel/`
- Use for:
  - keyboard prompts
  - gamepad prompts
  - touch prompt overlays and tutorial callouts

### Minimap pack

- Pack: `Minimap Pack`
- URL: <https://kenney.nl/assets/minimap-pack>
- Local destination: `art/kenney_minimap_pack/`
- Use for:
  - minimap frame
  - room markers
  - door and hazard icons

### Light mask pack

- Pack: `Light Masks`
- URL: <https://kenney.nl/assets/light-masks>
- Local destination: `art/kenney_light_masks/`
- Use for:
  - torch glows
  - portal pulses
  - damage flashes
  - fog-of-war and alarm masks

### Short SFX packs

- Pack: `Impact Sounds`
- URL: <https://kenney.nl/assets/impact-sounds>
- Local destination: `audio/kenney_impact_sounds/`
- Use for:
  - bomb impacts
  - crate destruction
  - enemy hit confirmation

- Pack: `UI Audio`
- URL: <https://kenney.nl/assets/ui-audio>
- Local destination: `audio/kenney_ui_audio/`
- Use for:
  - menu navigation
  - pickups
  - save/load feedback

- Pack: `Music Jingles`
- URL: <https://kenney.nl/assets/music-jingles>
- Local destination: `audio/kenney_music_jingles/`
- Use for:
  - room clear stingers
  - game over / unlock cues
  - placeholder menu music until longer loops are selected

### Font pack

- Pack: `Kenney Fonts`
- URL: <https://kenney.nl/assets/kenney-fonts>
- Local destination: `fonts/kenney_fonts/`
- Use for:
  - HUD font
  - menu font
  - pause / death / score overlays

## Optional Additions

- Tiled docs for map export:
  - <https://doc.mapeditor.org/en/stable/manual/export-generic/>
- Recommended format choice:
  - start with `Lua` map exports because this is a LOVE runtime
  - keep `JSON` as a fallback if external tooling around the Lua export becomes
    awkward

## Local Folder Contract

- `art/`:
  - atlases, tiles, UI sprites, portraits, prompts, masks
- `audio/`:
  - music loops, impact SFX, UI SFX, room clear cues
- `fonts/`:
  - bitmap or true-type fonts plus license text
- `maps/`:
  - Tiled source maps and exported runtime maps
- `shaders/`:
  - registered fragment shaders and compatibility-safe shader sources

## Acquisition Checklist

- Run the package tool from `pkgs/love2d/`:
  - `dart run tool/sync_relic_breach_assets.dart`
- Normalize the imported spritesheets into runtime-friendly RGBA atlases and
  convert luminance masks into transparent runtime light textures:
  - `dart run tool/normalize_relic_breach_atlas.dart`
- Use `--force` when you want to re-extract over an existing import:
  - `dart run tool/sync_relic_breach_assets.dart --force`
  - `dart run tool/normalize_relic_breach_atlas.dart --force`
- Download the Kenney packs listed above as zip archives.
- Keep each upstream pack in its own subdirectory instead of flattening.
- Preserve upstream license/readme files inside each pack folder.
- Create curated runtime atlases and trimmed subsets only after the original
  source pack is present in-tree.
- When the first real scene is assembled, add a second markdown file that maps
  exact upstream files to exact runtime paths.
