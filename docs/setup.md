# Setup

## Prerequisites

### Python & pip3

**macOS**
```bash
brew install python3
```

**Debian/Ubuntu**
```bash
sudo apt install python3-venv python3-pip
```

### Godot

Create a symlink to the Godot binary in the **project root**. This lets the Stop hook (`.claude/hooks/check.sh`) and other scripts invoke Godot via `./godot` regardless of where the engine lives on your machine. Shell aliases don't work here — they're only loaded by interactive shells, not by hook scripts.

**macOS**
```bash
ln -s /Applications/Godot.app/Contents/MacOS/Godot ./godot
```

**Linux**
```bash
ln -s /path/to/your/Godot ./godot
```

The symlink is gitignored, so each contributor sets up their own.

Verify:
```bash
./godot --version
```

---

## GDToolkit (GDScript linter/formatter)

Create a venv and install gdtoolkit 4.x:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install "gdtoolkit==4.*"
```

> Run `source .venv/bin/activate` at the start of each terminal session, or invoke `.venv/bin/gdlint` directly.

Verify installation:
```bash
gdlint --version
gdformat --version
```

---

## Lint

Run from the project root.

```bash
# Lint all files (excluding addons)
find . -name "*.gd" -not -path "./addons/*" | xargs gdlint

# Single file
gdlint src/main.gd
```

## Format

```bash
# Format all files (excluding addons)
find . -name "*.gd" -not -path "./addons/*" | xargs gdformat

# Single file
gdformat src/main.gd
```

---

