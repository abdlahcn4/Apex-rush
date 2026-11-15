# 🏎️ APEX RUSH

A 3D arcade racer built in **Godot 4.4** and shipped as a real **Android APK** and a real
**Windows build** from the same source tree.

The game began life as a browser prototype. It has since been rebuilt on a proper engine
with planar vehicle physics, five circuits and an imported-visual pipeline — no code-drawn
cars, buildings, trees or ground textures anywhere in the shipped scenes.

---

## What is in the game

**Vehicles.** Six tiers, all driving the imported *Car Concept* model (Khronos glTF Sample
Assets, CC-BY 4.0): named wheels, rims, brake discs and pads, full interior, working
steering, suspension travel, brake-light and headlight materials, and a paint picker that
restyles the live 3D preview in the garage.

**Circuits.** Five, each with its own sky, ground and dressing:

| Circuit | Character |
|---|---|
| Sunset Ring | Permanent circuit — grandstands, pit lane, kerbs, barriers, golden-hour HDRI |
| Harbour Night | Night city — towers, wet asphalt with real reflections, street lighting |
| Dune Pass | Desert highway — dunes, rock formations, dead trees, bleached ground |
| Cedar Pass | Forest climb — pine forest, ferns, moss-toned ground |
| Ridge Road | Mountain ridge — guardrail, cliff faces, scattered pines |

**Effects.** Exhaust backfire flames emitted from the modelled exhaust tips, blue nitro
flames from the same tips, tyre and drift smoke on the rear wheels, brake-light emissive
materials, headlight beams at night, speed-driven FOV.

**Audio.** All recorded samples, mixed live from vehicle state: three-layer engine
crossfade (idle → mid → top end), tyre scrub, wind rush, gear-shift clunk, blow-off valve on
lift, exhaust pop on upshift, pooled impacts, countdown and UI clicks.

**Front end.** Cinematic main menu over a live 3D turntable of the car, garage with paint
swatches and class stats, circuit select, settings (volume, graphics preset, fullscreen),
race HUD (circular speedometer, RPM strip with shift light, gear, nitro, lap, timer, best
lap), pause sheet, results.

**Controls.** Keyboard on PC, on-screen controls on touch devices only — the mobile overlay
is never shown on desktop. `W/S/A/D` or arrows drive, `SPACE` handbrake, `SHIFT` nitro,
`C` cycles chase / orbit / cockpit, `L` lights, `M` mute, `ESC` pause. Touch uses a steering
pad, throttle/brake pedals and nitro.

---

## Verifying the tree without running it

```bash
python3 tools/static_check.py     # resource paths, GLB integrity, class/function contracts, exports
```

It fails the build on a missing resource, a corrupt GLB, a call to a function that does not
exist, a vehicle-dictionary key the car does not provide, or a broken export preset.

## Building

Both targets are produced by `.github/workflows/android.yml` on a clean runner:

* **Android** — ARM64, touch, mobile renderer (GL compatibility), adaptive icon.
* **Windows** — 64-bit desktop, identical scenes and assets, no touch overlay.

## Asset provenance

Every imported file, its author, its licence and the mirror it came from is listed in
[`ASSETS.md`](ASSETS.md). The hero car is CC-BY 4.0 and requires attribution; the credit
ships in `godot/assets/vehicles/carconcept/LICENSE.md` and in-game.

## Honest status

* The project has **not** been runtime-tested by the author of the last round: the build
  environment has no GPU, display or Android toolchain, and gameplay/screenshot testing was
  explicitly out of scope. What *is* verified is static — syntax of every GDScript file,
  existence of every referenced resource, GLB header/payload integrity, the vehicle
  dictionary contract, and the export configuration.
* Turbo whistle, blow-off and exhaust-pop samples are Kenney CC0 recordings re-pitched and
  gated, not dedicated automotive samples — no reachable CC0 source had them.
