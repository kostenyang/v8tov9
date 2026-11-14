# F7 Apartment Walkthrough

Interactive 3D reconstruction of unit F7 (14F, "地上三至十四層平面圖") built with THREE.js r160 in a single `index.html`.

Open `index.html` over HTTP (any static server) – three.js is loaded as an ES module from jsDelivr.

## What is modelled
- Two layouts, switched with the **現況 · 無門牆 Current / 原始隔間 Original** button: the current state, where the wall carrying the two bedroom doors has been removed so both bedrooms open onto the living room (the wall between the bedrooms stays and ends in a half-height TV wall; the wardrobes are gone), and the original plan with that wall and its doors.
- Rooms scaled from the plan so the net interior floor area (walls and balcony excluded) is 23 坪 (`NET_PING` in `index.html`); the two bedrooms are the same size: living room, entry alcove, dining/kitchen, two bedrooms, hall, in-line bathroom, rear balcony, AC bay and the exterior ledge, plus the three corner columns.
- Walls with real openings, swing doors (click or press `E` to open/close), aluminium windows with glass and curtains.
- Furniture for every room, procedural materials (oak floor, porcelain and mosaic tiles, plaster, walnut, fabric), a 14th-floor city backdrop.
- Lighting: sun with shadows on a 06:00–20:00 slider, hemisphere sky light, ceiling lamps that come up at dusk.

## Controls
| Mode | Controls |
| --- | --- |
| Walk | click to capture the mouse · `W A S D` / arrows · `Shift` run · `E` door · `V` switch view |
| Plan | drag to pan · wheel / pinch to zoom · double-click a room to walk there |
| Touch | left half moves, right half looks |

Areas are shown in m² and 坪. Furniture sizes and the living-room window are typical for the plan, not surveyed.
