The current prototype shell still keeps most gameplay in `main.lua` so the
example boots immediately, but shared room wiring has started moving here.

Current files:

- `room_catalog.lua` exposes the ordered room list for the current slice

Planned split:

- `game.lua`
- `state/`
- `systems/`
- `ui/`
- `data/`
