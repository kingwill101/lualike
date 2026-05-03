# love2d_test_bed

Runnable Flutter example for `package:love2d`.

## Table Of Contents

- [Running The App](#running-the-app)
- [Included Demos](#included-demos)
- [Mobile Controls](#mobile-controls)
- [Vendored Demo Sources](#vendored-demo-sources)
- [Relic Breach Asset Sync](#relic-breach-asset-sync)

## Running The App

`flutter run -d linux` launches the Flame-based game center from `lib/main.dart`.

The game center is the only app entrypoint now.

## Included Demos

The menu currently includes:

- LOVE Example Browser
- Modern Pong
- Pocket Bomber
- Shader Explorer
- Relic Breach

The menu is responsive and scrollable on small screens.

## Mobile Controls

On compact screens, the launcher can show per-demo on-screen controls.

Current demo behavior:

- Modern Pong: left-side directional pad and a pause button
- LOVE Example Browser: direct touch interaction plus an on-screen `Esc` button
- Pocket Bomber: uses its own built-in touch controls
- Shader Explorer: left directional pad plus right-side action buttons
- Relic Breach: left directional pad plus right-side action buttons

Current limitation:

- the built-in virtual pad is digital key-based, not a true analog stick
- left and right control clusters are supported, but they currently emit
  discrete key presses rather than joystick axes

## Vendored Demo Sources

- LOVE Example Browser is cloned from
  [love2d-community/LOVE-Example-Browser](https://github.com/love2d-community/LOVE-Example-Browser)
  into [`assets/love_example_browser/`](./assets/love_example_browser/).
- Pocket Bomber is cloned from
  [chongdashu/love2d-pocket-bomber-game](https://github.com/chongdashu/love2d-pocket-bomber-game)
  into [`assets/pocket_bomber/`](./assets/pocket_bomber/).
- Modern Pong is cloned from
  [GwyrddGlas/Modern-Pong](https://github.com/GwyrddGlas/Modern-Pong) into
  [`assets/modern_pong/`](./assets/modern_pong/).
- Shader Explorer lives in
  [`assets/shader_explorer/`](./assets/shader_explorer/) and loads shader
  source from a copied local shader bundle in
  [`assets/shader_explorer/shaders/`](./assets/shader_explorer/shaders/).
- Relic Breach lives in [`assets/relic_breach/`](./assets/relic_breach/).

## Relic Breach Asset Sync

Relic Breach uses imported Kenney packs for the dungeon slice, character
sprites, audio, and fonts. Before running it from a fresh checkout, sync and
normalize the asset packs from `pkgs/love2d/`:

```bash
dart run tool/sync_relic_breach_assets.dart
dart run tool/normalize_relic_breach_atlas.dart
```
