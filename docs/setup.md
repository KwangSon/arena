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

Add an alias to your shell profile (`~/.zshrc` or `~/.bashrc`) pointing to the Godot binary:

```bash
alias godot="/Applications/Godot.app/Contents/MacOS/Godot"
```

Reload your shell:
```bash
source ~/.zshrc
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

