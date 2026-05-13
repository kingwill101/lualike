Tiled source maps and exported runtime maps live here.

Current layout:

- `first_vault.lua` is the current hand-authored flooded archive slice
- `ember_keep.lua` is the second authored room used for room-to-room flow
- `tiled/` is reserved for future `.tmx` and `.tsx` editor sources
- `runtime/` is reserved for future exported Lua or JSON map payloads

These room files are intentionally structured like lightweight exported maps:
they own walls, water zones, prop placements, player spawns, relic placement,
exit location, and crate spawns while `main.lua` only handles rendering and
gameplay systems.
