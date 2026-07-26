# ThinShot

A minimal, runnable **Godot 4** game project (GDScript). This repo is the
starting scaffold — open it in Godot, press play, and start building.

## Project layout

```
ThinShot/
├─ project.godot      # Godot project manifest (main scene, window, input map)
├─ icon.svg           # Project icon
├─ scenes/
│  └─ Main.tscn       # Main scene (loaded on run)
└─ scripts/
   └─ Main.gd         # Script attached to the main scene's root node
```

## 1. Install Godot 4.x

Download the **standard** (non-.NET) build of Godot 4 — GDScript needs no extra
toolchain.

- **Website:** https://godotengine.org/download (pick Godot 4.x, Standard)
- **macOS:** `brew install godot`
- **Windows:** `winget install GodotEngine.GodotEngine` (or download the `.exe`)
- **Linux:** your distro's package, Flatpak (`flatpak install flathub org.godotengine.Godot`), or the download above
- **Steam:** the free "Godot Engine" app

## 2. Get the project

```bash
git clone <this-repo-url>
cd ThinShot
```

## 3. Open the project

**Option A — Godot Project Manager (GUI):**
1. Launch Godot.
2. Click **Import**, browse to this folder, and select `project.godot`.
3. Click **Import & Edit**.

**Option B — command line:**
```bash
godot project.godot     # opens this project in the editor
# or, from the repo root:
godot .
```

## 4. Run it

- Press **F5** (▶ Run Project) — a 1152×648 window titled **ThinShot** opens
  showing the title screen. The console prints `ThinShot is running! Godot 4.x`.
- Press **F6** to run only the currently open scene.
- Press Spacebar while running to trigger the example `fire` input (logs `fire!`).

## 5. Build from here

- Edit `scripts/Main.gd` for game logic (`_ready()`, `_process()`).
- Edit `scenes/Main.tscn` in the editor to add nodes.
- Add new scenes under `scenes/` and scripts under `scripts/`.
- Input actions live in **Project → Project Settings → Input Map** (the `fire`
  action is already defined as an example).

> Note: Godot generates a local `.godot/` cache folder on first open — it's
> gitignored and safe to delete/regenerate.
