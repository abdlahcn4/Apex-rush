# Apex Rush — Godot 4 port (vertical slice)

A real Godot 4 project, not a wrapper. The Three.js sources stay in the zip at the repo root as
the reference implementation; this directory reimplements a first playable slice of them in
GDScript with Godot's own renderer, scene tree and input.

**Slice scope:** Sunset Ring circuit + Vortex GT + arcade drift handling + chase camera + HUD.
That is the "does it feel right?" checkpoint before porting modes, AI, garage and multiplayer.

## Run it

Requires **Godot 4.3 or newer** (standard build, Forward+ renderer). 4.4 / 4.5 are fine.

- **Editor:** open `godot/project.godot` and press **F5**.
- **CLI:** `godot --path godot/` (or `godot4 --path godot/`).

First launch builds the road, walls, scenery and lighting procedurally, so expect a second or two
of load time before the first frame.

### Controls

| Action | Keys |
|---|---|
| Throttle | `W` / `↑` (gamepad: right trigger, A) |
| Brake / reverse | `S` / `↓` (gamepad: B) |
| Steer | `A` `D` / `←` `→` (gamepad: left stick) |
| Handbrake | `Space` (gamepad: X) |
| Change camera | `C` — chase / far chase / first person |
| Reset car onto track | `R` |
| Quit | `Esc` |

## What was ported

| Original | Port | Notes |
|---|---|---|
| `public/js/track.js` — `CircuitTrack` | `scripts/track.gd` | Centripetal Catmull-Rom spline, 2 m arc-length resampling, `project()` / `pointAt()`, road + walls + edge lines + dashed lanes + start gantry |
| `public/js/vehicle.js` — `Vehicle` | `scripts/vehicle.gd` | Same arcade model: speed-sensitive steering, yaw from velocity rebuild, lateral grip, handbrake drift, wall clamping, gear/rpm, suspension pitch/roll |
| `public/js/cars.js` — `buildCar()` | `scripts/car_builder.gd` | Silhouette profile extruded across the width, cabin glass, lights, wing, wheels; all 6 car specs included |
| `public/js/game.js` — world + camera | `scripts/game.gd`, `scripts/camera_rig.gd` | Sunset sky, warm low sun, fog, mountains, ground, chase camera lag and speed FOV |
| `public/js/track.js` — scenery | `scripts/track.gd` | Trees / buildings scattered with the same road-distance rejection, via MultiMesh |
| three.js `ExtrudeGeometry` | `scripts/mesh_kit.gd` | `extrude_profile()` using `Geometry2D.triangulate_polygon` + explicit normals |
| `public/js/hud.js` (speed/gear) | `scripts/hud.gd` | Canvas HUD: speed, gear, rpm bar, drift flash, toasts |

`data/trackdata.json` is copied verbatim — it is already engine-neutral.

## What is not ported yet

- Race modes (time trial, AI race, traffic, checkpoint) and lap timing
- AI racers and traffic (`ai.js`)
- Garage, coins, upgrades, `localStorage` save (`save.js`) → `ConfigFile` / `user://`
- Procedural WebAudio engine sound (`audio.js`) → `AudioStreamGenerator`
- Touch controls and the DOM menus (`index.html`, `style.css`)
- LAN multiplayer (`multiplayer.js`, `src/server/realtime.ts`) — the natural Godot route is
  `ENetMultiplayerPeer` + `MultiplayerSynchronizer`, which would also remove the Node/Next.js host

## How far this slice was verified

The engine binary is not installable in the sandbox this was written in, so the project has not
been run through Godot itself. To keep that risk low:

1. Every script is parsed by **gdtoolkit 4.x** (a real GDScript 4 parser) — all clean.
2. The spline port was cross-checked against the actual `three.module.js` in Node: lap length
   3053.7 m vs 3053.4 m, identical 1527 samples, spacing uniform, coordinates within 3 cm.
3. `project()` — the function the wall collision depends on — was compared against the original
   `CircuitTrack.project()` at 30 positions around the lap: worst lateral error 1.4 cm.
4. The physics was executed head-to-head: original `Vehicle.update()` in Node vs a transliteration
   of `vehicle.gd` over 7 s of throttle, steering and handbrake — **bit-identical** state
   (position, heading, `vF`, `vR`, gear, rpm).

If Godot reports an error on first run, it is most likely a property name on a material, mesh or
environment resource — those are the parts no offline check can confirm. Send the error line and
it is a one-line fix.

## Suggested next steps

1. Lap timing + checkpoints + start countdown (mostly `track.gd` and `game.gd`).
2. AI opponents: reuse `point_at()` / curvature lookahead from the original `ai.js`.
3. Garage + save (`ConfigFile` in `user://`) and coins.
4. Traffic mode and near-miss scoring.
5. Multiplayer: ENet over LAN, room codes, 20 Hz snapshots like the Socket.IO server does today.
6. Touch HUD (`TouchScreenButton` / `Control`) for Android exports.
