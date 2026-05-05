# AGENTS.md

## Project Overview

This is a Godot 4.6 real-time multiplayer battle game project named "Arena".

### AI-First Code Strategy

This project follows an **AI-First Code Strategy** where GDScript takes priority over scene files:

- **GDScript-first approach**: All logic and functionality should be implemented in GDScript files first
- **Scene creation is limited**: Only create scenes when absolutely necessary:
  - Manual test entry points (`test/manual/`)
  - Complex map data requiring editor-based resource management
- **User confirmation required**: Before creating any scene file, always ask the user for confirmation
- **Script-based architecture**: Prefer code-based node creation and configuration over pre-built scenes
- **Code-based data management**: Use GDScript for all data definitions and instances instead of .tres resource files:
  - Define data structures (classes extending Resource) in GDScript
  - Create and store data instances in GDScript code
  - This approach enables faster iteration and better version control

## Project Structure

> See @docs/ARCHITECTURE.md for detailed architecture documentation.

```
arena/
├── project.godot          # Main project configuration
├── icon.svg               # Application icon
├── asset/                 # Game assets (images, models, audio)
├── src/                   # Source code (GDScript files)
│   ├── global/            # Global/autoload scripts
│   ├── data/              # Data structures and instances
│   └── ...                # Other source files
└── test/                  # Test directory
    ├── unit/              # Unit tests (GUT)
    └── manual/            # Manual test scenes
```

## Coding Standards

### GDScript Style Guide

Follow the official Godot GDScript style guide:

#### Naming Conventions

- **Classes/Nodes**: PascalCase (e.g., `PlayerController`, `EnemyAI`)
- **Functions**: snake_case (e.g., `get_player_position()`, `calculate_damage()`)
- **Variables**: snake_case (e.g., `player_health`, `move_speed`)
- **Constants**: SCREAMING_SNAKE_CASE (e.g., `MAX_SPEED`, `DEFAULT_HEALTH`)
- **Signals**: snake_case, past tense recommended (e.g., `health_changed`, `player_died`)
- **GDScript files**: snake_case (e.g., `player_controller.gd`, `enemy_ai.gd`)
- **Scene files**: snake_case (e.g., `main_menu.tscn`, `game_over.tscn`)
- **Data files**: snake_case (e.g., `character_data.gd`, `weapon_data.gd`)

#### File Organization

```gdscript
## Brief description of the script
## @author: Author name (optional)

class_name ClassName

# Signals
signal my_signal(param)

# Enums
enum State {IDLE, RUNNING, JUMPING}

# Constants
const MAX_VALUE := 100

# Exported variables
@export var speed: float = 10.0

# Child node references (pre-defined with types for script-based architecture)
var progress: ProgressBar
var label: Label
var button: Button

# Public variables
var public_var: int

# Private variables
var _private_var: String

# Virtual functions from parent class
func _ready() -> void:
    _setup_child_nodes()

func _process(delta: float) -> void:
    pass

# Setup functions (for script-based node creation)
func _setup_child_nodes() -> void:
    progress = ProgressBar.new()
    add_child(progress)
    
    label = Label.new()
    add_child(label)

# Public functions
func public_function() -> void:
    pass

# Private functions
func _private_function() -> void:
    pass
```

#### Static Typing

Always use static typing for better code completion and error detection:

```gdscript
# Good
var health: int = 100
func get_name() -> String:
    return "Player"

# Avoid
var health = 100
func get_name():
    return "Player"
```

### Scene Organization

- One main scene per feature/screen
- Use inheritance for similar nodes
- Keep scenes modular and reusable
- Use node paths relative to the current node when possible

> See [DESIGN.md](DESIGN.md) for detailed scene structure and UI design guidelines.

### Best Practices

1. **Use type hints** for all variables and function return types
2. **Document complex functions** with docstrings (## comments)
3. **Use signals** for decoupled communication between nodes
4. **Avoid hardcoded values** - use @export variables or constants
5. **Use code-based data** - define data structures and instances in GDScript instead of .tres files
6. **Profile performance** regularly, especially for mobile targets
7. **Use groups** sparingly - prefer direct references when possible
8. **Code defensively with `assert`** - fail fast instead of silently propagating null/invalid state (see below)

### Defensive Coding (MANDATORY)

Godot's silent null-propagation has caused significant debugging pain on this project. **Use `assert` aggressively to fail fast at the source of bugs rather than letting nulls/invalid state spread.**

#### Rules

1. **Assert all `@onready` / node references after acquisition** - `get_node`, `find_child`, `get_parent`, child node lookups can all return null silently.
2. **Assert function arguments** that must not be null or out-of-range, especially at API boundaries.
3. **Assert preconditions** before mutating state (e.g., array index bounds, dictionary keys, expected node types).
4. **Assert postconditions** when a function promises to return a non-null value or a value in a range.
5. **Assert signal connections succeeded** - `connect()` returns an error code; verify it.
6. **Always include a message** in `assert()` so failures explain what was expected.

> Note: `assert()` is stripped from release builds. It is for catching developer bugs during development, not for runtime validation of user input or network data — those still need real error handling.

#### Examples

```gdscript
# Node references — assert immediately
func _ready() -> void:
    _hud = get_node("HUD") as PlayerHUD
    assert(_hud != null, "HUD node missing — check scene tree")

    var sprite := find_child("Sprite") as Sprite2D
    assert(sprite != null, "Sprite2D child not found under %s" % name)

# Function arguments
func apply_damage(target: CharacterBase, amount: int) -> void:
    assert(target != null, "apply_damage: target is null")
    assert(amount >= 0, "apply_damage: negative damage %d" % amount)
    target.hp -= amount

# Preconditions / lookups
func get_player_by_id(player_id: String) -> PlayerSession:
    assert(_players.has(player_id), "Unknown player_id: %s" % player_id)
    return _players[player_id]

# Casts — assert the cast succeeded
var character := node as CharacterBase
assert(character != null, "Expected CharacterBase, got %s" % node.get_class())

# Signal connections
var err := button.pressed.connect(_on_button_pressed)
assert(err == OK, "Failed to connect button.pressed: %d" % err)
```

#### Anti-patterns

```gdscript
# BAD — silent null propagation
func _ready() -> void:
    _hud = get_node("HUD")  # if missing, fails 100 lines later with confusing error

# BAD — assert without a message
assert(target != null)  # gives no context when it fires

# BAD — using assert for runtime/network validation (gets stripped in release)
assert(packet.is_valid())  # use real error handling instead
```

### Linting & Formatting

This project uses [GDScript Toolkit](https://github.com/Scony/godot-gdscript-toolkit) for code linting and formatting.

> See [docs/setup.md](docs/setup.md) for installation and usage instructions.

## Testing

This project uses GUT (Godot Unit Testing) for unit tests.

### Test Structure

- **test/unit/**: Unit tests run automatically by GUT
- **test/manual/**: Manual test scenes that you run directly for manual verification

### Running Tests

#### Running Unit Tests (GUT)

```bash
# Run all unit tests
./godot -d -s --path "$PWD" addons/gut/gut_cmdln.gd

# Run specific test file
./godot -d -s --path "$PWD" addons/gut/gut_cmdln.gd -gtest=test_example.gd
```

### Writing Unit Tests

Place unit test files in `test/unit/` directory. Follow GUT naming conventions:

- Test files should start with `test_` (e.g., `test_player.gd`)
- Test methods should start with `test_` (e.g., `func test_movement():`)

#### Best Practices

**Always use autofree methods** to prevent memory leaks and orphan detection:

```gdscript
# Use autofree for manually created nodes
var player: CharacterBase = autofree(CharacterBase.new())

# Use add_child_autofree for nodes that need to be in tree
var hud: HUD = add_child_autofree(HUD.new())

# Use autoqfree for queue_free scenarios
var effect: Node3D = autoqfree(Node3D.new())
```

**Use mocks for isolated testing**:

```gdscript
func test_combat_with_mock() -> void:
    var mock_enemy = double(CharacterBase).new()
    autofree(mock_enemy)
    
    # Test without real dependency
    stub(mock_enemy, "take_damage").to_return(10)
```

**Available Autofree Methods**:
- `autofree(obj)` - calls `free()` after each test
- `autoqfree(obj)` - calls `queue_free()` after each test
- `add_child_autofree(node)` - adds to tree + frees after each test
- `add_child_autoqfree(node)` - adds to tree + queue_frees after each test

Example test file:

```gdscript
extends GutTest

func test_example() -> void:
    assert_eq(1 + 1, 2, "Basic math should work")

func test_player_initialization() -> void:
    var player: CharacterBase = autofree(CharacterBase.new())
    assert_not_null(player)
    # No need to call player.free() - autofree handles it
```
