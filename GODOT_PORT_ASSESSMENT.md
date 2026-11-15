# Apex Rush — Godot Feasibility Assessment

**Question:** can this game run in Godot without changing anything?

**Short answer: no.** Apex Rush is a browser game written in JavaScript against Three.js and the DOM.
Godot 4 cannot execute JavaScript at all, has no importer for `.js` / `.html` / `.css`, and has no
Three.js equivalent to link against. Nothing in this repository is loadable by Godot — there is no
"add the folder to a Godot project and press F5" path.

The rest of this document is the inspection it's based on, plus the realistic options.

---

## 1. What the project actually is

The repository ships a single archive, `multiplayer-3d-racing-game.zip` (2.3 MB, 48 entries).
Contents:

| Area | Files | Lines | Technology |
|---|---|---|---|
| Game runtime | `public/js/*.js` (10 files) | ~3,230 | ES modules, Three.js r187, WebGL2, Canvas2D, WebAudio |
| Game URL / UI | `public/index.html`, `public/style.css` | ~490 | HTML + CSS DOM screens (menu, garage, HUD, touch pads) |
| Vendored libs | `public/vendor/three.module.js`, `three.core.js`, `socket.io.min.js` | 2.2 MB | pre-built browser bundles |
| Multiplayer server | `src/server/realtime.ts` | 611 | Node + Socket.IO, authoritative race state, 20 Hz snapshots |
| Web host | `next.config.ts`, `server.js`, `src/app/**`, `src/instrumentation.ts` | ~150 | Next.js 16 on Node, one port for HTTP + WebSocket, LAN/QR helpers |
| Persistence | `src/db/*`, `src/app/api/scores/route.ts` | ~85 | Postgres + Drizzle (LAN leaderboard) |

Gameplay breakdown (`public/js`):

- `game.js` (1,067) — boot, renderer, camera, race director, modes, money/upgrade flow
- `track.js` (660) — Sunset Ring circuit built procedurally from `trackdata.json` points, plus an
  endless highway mode; spline road mesh, walls, scenery, GLSL sky dome, Canvas2D textures
- `cars.js` (332) — 6-car catalogue, procedural low-poly car models from box/cylinder primitives
- `multiplayer.js` (375) — Socket.IO client, 100 ms interpolation buffer
- `vehicle.js` (211) — arcade drift physics, hand-written (no physics engine)
- `hud.js` (176) — speedo, minimap and FX drawn on HTML canvases
- `ai.js` (160) — AI racers + traffic
- `audio.js` (99) — engine/tyre/wind synthesis with WebAudio oscillators and noise buffers
- `save.js` (84) — `localStorage` progress + settings
- `input.js` (69) — keyboard + touch buttons/wheel

Three.js features used: `WebGLRenderer` (PCF shadows, PMREM environment), `MeshStandardMaterial`,
`MeshPhysicalMaterial`, `InstancedMesh`, `ExtrudeGeometry`, `CatmullRomCurve3`, `Sprite`s,
`CanvasTexture`s, a custom `ShaderMaterial` sky with fBm noise, and `Fog`.

There are **no 3D asset files** anywhere — no `.glb`, `.gltf`, `.fbx`, `.obj`, `.png` models or
textures. Every mesh, material and texture is generated at runtime in JavaScript.

---

## 2. Why Godot can't just load it

1. **No JS runtime.** Godot 4 scripts are GDScript, C# or C++ (GDExtension). There is no
   JavaScript binding, so `game.js` and friends cannot be executed inside Godot, not even as a
   "language".
2. **No asset importer for web code.** Godot imports glTF/OBJ/PNG/WAV/etc. into `.res`/`.import`
   files. A `.js` or `.html` file is treated as opaque text.
3. **Three.js is a browser library.** `three.module.js` needs a WebGL2 canvas, `window`,
   `document` and `requestAnimationFrame`. Godot's renderer (Vulkan/GLES3 → WASM for web export)
   is not reachable from JavaScript and has an entirely different API (`Node3D`, `MeshInstance3D`,
   `StandardMaterial3D`, `Environment`).
4. **The game is DOM-shaped.** Every menu, HUD, dialog and touch control is HTML/CSS operated via
   `document.getElementById` — 245 lines of HTML and a 20 KB stylesheet. Godot equivalents are
   `Control` nodes and a `.tscn` scene tree; nothing maps automatically.
5. **Browser-only APIs.** `localStorage` (`save.js`), `AudioContext` oscillators (`audio.js`),
   `fetch` + `<canvas>` text rendering (`hud.js`, `cars.js`), `matchMedia`/`navigator` feature
   detection, and the Socket.IO client. Each needs a different Godot API (`ConfigFile`/`FileAccess`,
   `AudioStreamGenerator` or pre-baked `.ogg` loops, `HTTPRequest`, `WebSocketPeer`/`ENet`).
6. **The multiplayer layer is Node.** `realtime.ts` is a 611-line authoritative Socket.IO server.
   Godot has no Socket.IO client; you'd either bridge it over plain WebSocket or replace it with
   Godot's high-level multiplayer (`ENetMultiplayerPeer` + `MultiplayerSynchronizer`), which for a
   LAN game would also remove the Node/Next.js dependency entirely.

The closest "run it unmodified" trick is embedding a Chromium view inside a Godot window with a
community plugin. That needs a native plugin, a new Godot project and a Windows/macOS-only build —
and the game would still be rendering through Chromium's WebGL, not Godot's engine. It changes
things *and* defeats the purpose.

---

## 3. The good news for a real port

The architecture is friendlier to porting than most web games:

- **No art pipeline to migrate.** Procedural geometry (boxes, cylinders, splines, extruded shapes)
  maps cleanly onto Godot `MeshInstance3D`, `ArrayMesh`/`SurfaceTool`, `Path3D` + `Curve3D` and
  `CSGPolygon3D`. You rebuild it in code, not by converting assets.
- **No physics engine to match.** `vehicle.js` is ~200 lines of plain arithmetic on velocity,
  heading and drift. It ports to GDScript almost line for line.
- **Data is already engine-neutral.** `trackdata.json` (15 spline points, road width, lane count,
  checkpoint radius) and the `CAR_SPECS` table are plain data — reusable verbatim.
- **The shaders are simple GLSL.** The sky dome fBm shader becomes a Godot `ShaderMaterial` or a
  `Sky` shader with modest edits.
- **The sound is synthesised**, so it can be regenerated with `AudioStreamGenerator`, or baked once
  and shipped as loops (easier and cheaper on mobile).

Rough port cost, one experienced developer, single-player parity first:

| Slice | Work | Estimate |
|---|---|---|
| Project skeleton, camera, track mesh, one car, driving | rewrite `track.js` + `vehicle.js` + `cars.js` core | 1–2 weeks |
| Modes, HUD, garage, save, audio, touch UI | rewrite `game.js` + `hud.js` + UI scenes | 2–3 weeks |
| LAN multiplayer | rewrite `realtime.ts` logic (ENet or WS bridge) | 1–2 weeks |
| Polish, mobile export, performance | — | 1–2 weeks |

So realistically **5–9 weeks of focused work** for a faithful Godot version, versus zero to keep the
browser build. This is a rewrite, not a migration; the JS files stay behind as the design reference.

---

## 4. Options

**A. Real Godot port (recommended if the goal is native builds / console / Steam).**
Rewrite as a Godot 4 project: GDScript, `Node3D` scenes, `Control` UI, `AudioStreamPlayer`, LAN
multiplayer via ENet. Full parity is the 5–9 week estimate above. Start with a vertical slice
(highway + one car + driving feel) to validate the feel before porting menus and modes.

**B. Ship the existing web build as an app (0 changes to game code).**
Wrap `public/` in Tauri, Electron or Capacitor. Desktop and mobile installers, no Godot involved,
no rewrite. Trades native engine features for a Chromium runtime (~40–100 MB).

**C. Embed a browser in Godot (not recommended).**
Native WebView plugin inside Godot; Windows/macOS only, no web export, no mobile, extra CEF
payload, and the game still isn't running on Godot's renderer.

**D. Keep it in the browser and improve it there.**
The current stack (Next.js + Socket.IO + Three.js) is already the shortest path to "playable
everywhere": zero install, phones join over LAN via QR. If Godot wasn't a hard requirement, this
is the cheapest option by far.

Nothing above is "run it in Godot unmodified". Option A is the only true Godot outcome; B is the
only zero-change outcome.

---

## 5. Notes on verification

- Godot is not installed in this workspace and cannot be fetched from the allowed package
  registries, so no Godot project was built or launched here. The engine limitations above are
  documented Godot 4 behaviour, not guesses.
- The game itself was inspected statically. I did not run `npm install` / `next build`, so the
  browser build is unverified at runtime — that's a separate, quick check if wanted.
