---
Not defined yet.
---

# Design System (Godot 4)

## Overview
Minimal, script-driven UI on top of Godot's built-in controls. No custom styling at this stage.

Principles:
- Use Godot's built-in nodes as-is (`Button`, `Label`, `LineEdit`, containers).
- No custom Theme, StyleBox, or font overrides.
- `.tscn` defines structure; behavior lives in `.gd` scripts.

## Scene Structure

Scene root is always `Node2D`. Game logic and world objects live in the `Node2D` tree.

UI (HUD, shop, menus) uses a `CanvasLayer` under `Node2D`, with `Control` nodes inside. `CanvasLayer` draws in screen space, decoupled from the camera.

```
Main (Node2D)
├── World (Node2D)              # game world, characters, enemies
└── UI (CanvasLayer)            # screen-anchored UI
    ├── HUD (Control)
    └── Shop (Control)
```

Guidance:
- Screen-anchored UI (HUD / shop / menu): `Node2D` → `CanvasLayer` → `Control`.
- Simple panel that may follow the camera: `Control` directly under `Node2D`.
- Fullscreen menu / title: `Node2D` → `CanvasLayer` → `Control` anchored to full rect.

## Components

Use default appearance of built-in nodes. Set text/values only.
- `Button`, `Label`, `LineEdit` — plain nodes, no styling.
- Layout via `VBoxContainer`, `HBoxContainer`, `MarginContainer`. Avoid hard-coded pixel positions.

## Do's and Don'ts
- Do: structure UI as `Node2D` → `CanvasLayer` → `Control`.
- Do: let containers handle alignment.
- Do: keep behavior in `.gd`, keep `.tscn` for structure.
- Don't: add Theme resources, StyleBox, or font overrides at this stage.
