🏎️ Apex Rush – 3D Racing Game

Welcome to Apex Rush, an exciting 3D car racing game playable directly in your browser!

🎮 Features

- 3D driving experience powered by Three.js.
- Multiple cars to unlock and customize.
- Free Drive mode.
- Time Trial mode.
- AI Racing mode.
- Traffic Racing mode.
- Checkpoint Challenge.
- Car upgrades and customization.
- Automatic progress saving.
- Mobile and PC support.
- Touch controls for smartphones.
- Keyboard controls for PC.

📱 Platform Support

- Desktop: Windows, Linux and macOS browsers.
- Mobile: Android and iOS browsers.

🚀 Installation

Make sure Node.js is installed.

npm install
npm run build
node server.js

Then open your browser and visit:

http://localhost:3000

🛠️ Technologies

- HTML5
- CSS3
- JavaScript
- Three.js
- Node.js
- Socket.IO

🌐 Project

Apex Rush is designed to deliver an enjoyable racing experience on both desktop and mobile devices.

📄 License

All rights reserved unless otherwise specified.

## Godot port

This game is JavaScript/Three.js and cannot be loaded by Godot as-is — see
[GODOT_PORT_ASSESSMENT.md](GODOT_PORT_ASSESSMENT.md) for the inspection and why.

A real Godot 4 port has been started in [`godot/`](godot/README.md): a playable vertical slice with
the Sunset Ring circuit, the Vortex GT, the original arcade drift physics, chase camera and HUD.

Open `godot/project.godot` in Godot 4.3+ and press F5.

## Controls

Desktop and phone share one build; the on-screen pads only appear on a device that reports
a touchscreen.

| Action | Keyboard | Touch |
|---|---|---|
| Accelerate | `W` / `Up` | GAS pad |
| Brake / reverse | `S` / `Down` | BRK pad |
| Steer | `A` `D` / `Left` `Right` | `<` `>` pads |
| Handbrake | `Space` | HAND pad |
| Nitro | `Shift` | NOS pad |
| Pause | `Esc` / `P` | `II` button |
| Camera mode | `C` | CAM button |
| Reset car | `R` | RST button |
| Mute | `M` | - |
| **Orbit the camera 360 degrees** | drag with the left mouse button | drag anywhere that is not a pad |

The camera eases back behind the car 2.5 s after you let go of a drag, and all of its
motion (position, distance, height, look target, field of view) is filtered so high speed
does not make it vibrate.
