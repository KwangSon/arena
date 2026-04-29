# Arena - Multi-Mode Battle Game Architecture

## Overview

Arena is a Godot 4.6 mobile **2D** multiplayer battle game built on a **referee-authoritative** model. One Godot instance runs as the *referee* (authoritative server) and the rest run as *players* (clients). All gameplay decisions — movement validation, hit detection, victory checks, RNG rolls — are made by the referee.

**Current target mode: TDM (Team Deathmatch)** — 3v3 (6 players + 1 referee instance).

### Network Stack at a Glance

| Layer | Stage 1 (current) | Stage 2 (later) |
|-------|-------------------|-----------------|
| Auth / Account | none / local stub | Nakama |
| Matchmaking | manual launch | Nakama matchmaker |
| Lobby / Shop persistence | in-memory | Nakama storage |
| **Game traffic (input, state, RPC)** | **Godot ENet, direct client↔referee** | **Same — Nakama does NOT relay game packets** |

Nakama is added later strictly as a control plane for matchmaking, accounts, and persistence. It never intermediates gameplay packets. After Nakama hands a client a referee endpoint, the client connects to the referee directly via Godot's high-level multiplayer (ENet).

## Application Modes

Selected at launch via command-line argument.

### Player Mode (default)
- Full UI (Login, Lobby, Shop, Character Select, Game, Result)
- For end-users
- Default when launched without flags

### Referee Mode
- Authoritative game logic, no UI required
- Can run headless for server deployment
- Activated via `--mode=referee`

```bash
# Player (default, with UI)
godot --path .

# Referee (development, with debug UI)
godot --path . -- --mode=referee

# Referee (production, headless)
godot --path . --headless -- --mode=referee --match-id=xxx
```

## Game Modes

Each game mode implements `IModeManager` for a consistent lifecycle.

### TDM (Team Deathmatch) — current
- 6 players (3v3), 1 referee
- Win condition: all enemy team members eliminated

### Future Modes
- **FFA** — every player for themselves
- **Capture The Flag** — objective-based team play
- **King of the Hill** — area control

## Screen Flow (Player Mode)

```
┌──────────┐     ┌──────────┐     ┌──────────────┐     ┌──────────────────┐
│  LOGIN   │────▶│  LOBBY   │────▶│ MATCHMAKING  │────▶│ CHARACTER SELECT │
└──────────┘     └────┬─────┘     └──────────────┘     └────────┬─────────┘
                      │                                          │
                      ▼                                          ▼
                 ┌──────────┐                            ┌──────────────┐
                 │   SHOP   │                            │     GAME     │
                 └──────────┘                            └──────┬───────┘
                                                                │
                                                                ▼
                                                        ┌──────────────┐
                                                        │    RESULT    │
                                                        └──────────────┘
```

| Screen | Purpose | Key Features |
|--------|---------|--------------|
| Login | Authentication | Local stub (Stage 1) → Nakama login (Stage 2) |
| Lobby | Main hub | Matchmaking, shop access, deck editing |
| Shop | Card purchase | Buy cards with in-game currency |
| Matchmaking | Queue waiting | Queue status, estimated time |
| Character Select | Pre-match setup | Choose character, equip cards |
| Game | Gameplay | HUD, joystick, combat |
| Result | Post-match | Stats, rewards, return to lobby |

## Network Architecture

### Stage 1 — Direct ENet (current)

Godot's high-level multiplayer over ENet. The referee instance creates an ENet server; player instances connect as clients. There is no external matchmaking — instances are launched manually or via the editor's "Run Multiple Instances" feature.

```
                  ┌─────────────────────┐
                  │  REFEREE INSTANCE   │
                  │  (Godot, ENet srv)  │
                  │  - Authority        │
                  │  - Hit detection    │
                  │  - State broadcast  │
                  └──────────┬──────────┘
                             │ ENet (port 7777)
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
  ┌──────────┐         ┌──────────┐         ┌──────────┐
  │ CLIENT A │         │ CLIENT B │  ...    │ CLIENT F │
  │ (Godot)  │         │ (Godot)  │         │ (Godot)  │
  └──────────┘         └──────────┘         └──────────┘
```

State sync uses `MultiplayerSpawner` + `MultiplayerSynchronizer`. Discrete events (skill activation, hit results) flow over RPCs.

### Stage 2 — Adding Nakama

Nakama joins as a metadata layer for matchmaking, auth, and persistence. **Game traffic still flows over ENet between client and referee**; Nakama only tells the client where the referee is.

```
┌─────────────────────────────────────────┐
│              NAKAMA SERVER              │
│  - Auth / accounts                      │
│  - Matchmaking (3v3)                    │
│  - Card / shop persistence              │
│  - Match registry (referee endpoints)   │
└──────────────────┬──────────────────────┘
                   │ HTTPS / WebSocket (control plane only)
        ┌──────────┼──────────────┐
        ▼          ▼              ▼
   ┌────────┐ ┌────────┐ ... ┌────────┐
   │CLIENT A│ │CLIENT B│     │CLIENT F│
   └───┬────┘ └───┬────┘     └───┬────┘
       │          │              │
       │   ENet (data plane, after match assigned)
       └──────────┼──────────────┘
                  ▼
            ┌────────────┐
            │  REFEREE   │
            └────────────┘
```

### Referee Responsibilities
- **Movement validation** — speed limits, dash availability
- **Hit detection** — projectile collision, melee range
- **Damage application** — apply, check death
- **Resource management** — MP/BP usage and regen
- **Game state** — alive players, victory check
- **RNG** — all card effect rolls (anti-cheat)

### Client Responsibilities
- **Input** — joystick, skill buttons
- **Visual feedback** — animations, predicted effects
- **UI updates** — HP bars, cooldowns
- **Network sync** — send inputs, receive state

## Latency Strategy

A naive server-authoritative model where the client just *waits* for referee responses produces unplayable lag at mobile RTT (50–150ms+). The architecture must include client-side compensation.

### Adopted Approach (default)

| Concern | Strategy |
|---------|----------|
| **Own movement** | Client-side prediction + server reconciliation. Client moves immediately on input; referee validates and broadcasts authoritative position; client snaps/lerps to correct on mismatch. |
| **Other players' movement** | Interpolation buffer (~100ms). Render slightly behind authoritative state for smoothness. |
| **Skill activation** | Client plays animation immediately on tap; sends RPC. Referee validates cooldown/range/resources and broadcasts result. Client cancels visuals on rejection. |
| **Hit detection** | Referee-side using server-authoritative positions. **No lag compensation / rewind in v1** — accept that fast-moving targets may feel "dodgy" on bad connections. Revisit if playtesting demands it. |
| **Resource (MP/BP) regen** | Computed locally for UI; referee is authoritative. UI snaps to referee value on mismatch. |

### Out of Scope (for now)
- Server-side rewind / lag compensation for hit detection
- Rollback netcode
- Delta-compressed snapshots beyond Godot's built-in `MultiplayerSynchronizer`

## Disconnect Policy

Disconnect handling is **referee-authoritative** and does **not** pause the match.

- **Grace period:** `10 seconds`
- **Match flow during grace:** the match continues normally
- **Referee behavior:** if a client stops responding, the referee immediately clears that player's input and freezes their character in place
- **Timeout result:** if the player does not recover within the 10-second grace window, that player forfeits the match
- **Match end:** after a disconnect timeout forfeit, the referee ends the match and broadcasts the result

This policy is intended for unstable mobile connections: temporary packet loss or a short connection drop should not cause an instant loss, but the game should also remain resistant to pause abuse.

These can be added later if data shows they are needed.

## Directory Structure

```
arena/
├── project.godot
├── src/
│   ├── main.gd                    # Entry point + mode dispatch
│   ├── main.tscn                  # Minimal main scene
│   │
│   ├── global/                    # Autoloads
│   │   ├── app_mode.gd            # PLAYER vs REFEREE detection (Node autoload)
│   │   └── game_events.gd         # Global signal bus (Node autoload)
│   │
│   ├── screen/                    # UI screens (Player mode only)
│   │   ├── screen_manager.gd
│   │   ├── login_screen.gd
│   │   ├── lobby_screen.gd
│   │   ├── shop_screen.gd
│   │   ├── matchmaking_screen.gd
│   │   ├── character_select_screen.gd
│   │   ├── game_screen.gd
│   │   └── result_screen.gd
│   │
│   ├── referee/                   # Referee-only logic
│   │   ├── referee_manager.gd
│   │   └── referee_starter.gd     # Headless bootstrap
│   │
│   ├── network/
│   │   ├── nakama_client.gd       # Stage 2: Nakama wrapper
│   │   ├── match_manager.gd       # ENet match session
│   │   └── synchronizer.gd        # MultiplayerSynchronizer wrapper
│   │
│   ├── game/
│   │   ├── mode_interface.gd      # IModeManager base class
│   │   ├── game_settings.gd       # Constants (static, not an autoload)
│   │   ├── tdm_manager.gd         # TDM mode logic
│   │   ├── game_state.gd
│   │   ├── team_manager.gd
│   │   └── victory_checker.gd
│   │
│   ├── character/
│   │   ├── character_base.gd      # Base CharacterBody2D
│   │   ├── character_spawner.gd
│   │   ├── movement_controller.gd
│   │   └── skill_controller.gd
│   │
│   ├── combat/
│   │   ├── hit_detector.gd        # Referee-side
│   │   ├── damage_calculator.gd
│   │   ├── card_effect_processor.gd  # Referee rolls RNG
│   │   ├── projectile.gd
│   │   └── melee_attack.gd
│   │
│   ├── input/
│   │   ├── joystick.gd
│   │   ├── input_processor.gd
│   │   └── dash_detector.gd
│   │
│   ├── data/                      # Code-based data (no .tres files)
│   │   ├── enums.gd
│   │   ├── character_data.gd      # CharacterData Resource definition
│   │   ├── character_definitions.gd
│   │   ├── skill_data.gd
│   │   ├── skill_definitions.gd
│   │   ├── card_data.gd
│   │   └── card_definitions.gd
│   │
│   └── ui/
│       ├── player_hud.gd
│       ├── referee_hud.gd
│       ├── health_bar.gd
│       ├── resource_bar.gd
│       ├── skill_button.gd
│       └── joystick_ui.gd
│
└── test/
    ├── unit/                      # GUT tests
    │   ├── test_sanity.gd
    │   ├── test_combat.gd
    │   ├── test_movement.gd
    │   └── test_card_effects.gd
    └── manual/                    # Multi-instance manual tests
        ├── test_combat.gd         # ENet + spawn + RPC smoke test
        └── test_combat.tscn
```

> `CharacterData` lives at `src/data/character_data.gd` only. `src/character/` holds runtime character classes (`character_base.gd`), not data definitions.

## Core Data Types

### AppMode (Autoload)
```gdscript
## Application mode — Player vs Referee. Detected from cmdline args.
class_name AppMode extends Node

enum Mode { PLAYER, REFEREE }

var current_mode: Mode = Mode.PLAYER

func _ready() -> void:
    var args: Array = OS.get_cmdline_args()
    current_mode = Mode.REFEREE if "--mode=referee" in args else Mode.PLAYER

func is_player_mode() -> bool:
    return current_mode == Mode.PLAYER

func is_referee_mode() -> bool:
    return current_mode == Mode.REFEREE
```

### GameEvents (Autoload)
```gdscript
## Global signal bus for decoupled communication.
class_name GameEvents extends Node

# Match
signal match_started(match_id: String)
signal match_ended(winner_team: int)

# Character
signal character_spawned(character_id: String, team_id: int)
signal character_died(character_id: String, team_id: int)
signal character_hit(attacker_id: String, target_id: String, damage: int)

# Resources
signal hp_changed(character_id: String, current: int, maximum: int)
signal mp_changed(character_id: String, current: int, maximum: int)
signal bp_changed(character_id: String, current: int, maximum: int)

# Screens
signal screen_requested(screen_name: String)
signal screen_transitioned(from_screen: String, to_screen: String)
```

### GameSettings (Static Constants — NOT an Autoload)

Just compile-time constants. Access as `GameSettings.MATCH_SIZE` from any script. No instance, no autoload registration.

```gdscript
class_name GameSettings

# Match
const MATCH_SIZE: int = 6
const TEAM_SIZE: int = 3

# Resources
const DEFAULT_MAX_HP: int = 100
const DEFAULT_MAX_MP: int = 100
const DEFAULT_MAX_BP: int = 100

# Dash
const BP_DASH_DRAIN_PER_SEC: float = 25.0  # BP drained per second while dashing
const DOUBLE_TAP_TIME_WINDOW: float = 0.3

# Regen (per second)
const DEFAULT_MP_REGEN: float = 1.0
const DEFAULT_BP_REGEN: float = 5.0

# Network
const DEFAULT_SERVER_PORT: int = 7777
const RECONNECT_TIMEOUT: float = 10.0
```

### IModeManager (Base Class)

GDScript has no real interfaces, so `IModeManager` is a base class whose virtual methods `assert(false, ...)` if not overridden. This catches "forgot to override" bugs at the source instead of letting them silently no-op.

```gdscript
## Base class for all game modes. Subclasses MUST override every method.
class_name IModeManager extends RefCounted

func start_match(_players: Array[PlayerSession]) -> void:
    assert(false, "IModeManager.start_match must be overridden")

func process(_delta: float) -> void:
    assert(false, "IModeManager.process must be overridden")

## Returns winning team id (1 or 2), or -1 if match is still ongoing.
func check_victory() -> int:
    assert(false, "IModeManager.check_victory must be overridden")
    return -1

func get_spawn_positions(_team_id: int) -> Array[Vector2]:
    assert(false, "IModeManager.get_spawn_positions must be overridden")
    return []
```

### CharacterData

```gdscript
class_name CharacterData extends Resource

var id: String
var display_name: String

# Stats
var max_hp: int = 100
var max_mp: int = 100
var max_bp: int = 100
var move_speed: float = 300.0

# Skills
var skill_1: SkillData
var skill_2: SkillData
var ultimate: SkillData

# Regen (per second)
var mp_regen: float = 1.0
var bp_regen: float = 5.0
```

> Per the AI-First Code Strategy, all instances are constructed in code (`character_definitions.gd`). No `.tres` files, no `@export` annotations.

### SkillData

```gdscript
class_name SkillData extends Resource

enum Type { MELEE, PROJECTILE, AOE }

var id: String
var display_name: String
var skill_type: SkillData.Type
var damage: int
var range: float
var cooldown: float
var mp_cost: int = 0
var projectile_speed: float = 0.0  # 0 = melee/AOE
```

### CardData

Cards are equipped before the match and trigger passively during combat. **The referee rolls all RNG** to prevent client-side cheating.

```gdscript
class_name CardData extends Resource

enum TriggerEvent {
    ON_HIT,       # fires when this player deals damage
    ON_TAKE_HIT,  # fires when this player receives damage
    PASSIVE,      # applied once at character spawn (stat modifier)
}

enum EffectType {
    # ON_HIT effects
    CRITICAL_HIT,    # prob% → damage × 2
    LIFESTEAL,       # prob% → heal attacker by effect_value% of damage dealt
    EXTRA_DAMAGE,    # prob% → damage += base_damage × effect_value

    # ON_TAKE_HIT effects
    DODGE,           # prob% → negate all incoming damage
    THORNS,          # always → reflect effect_value% of incoming damage to attacker

    # PASSIVE effects (applied at spawn, no probability roll)
    MOVE_SPEED_BONUS,     # move_speed *= (1 + effect_value)
    MP_REGEN_BONUS,       # mp_regen  *= (1 + effect_value)
    COOLDOWN_REDUCTION,   # stored on CharacterBase; SkillExecutor reads it per-cast
}

var id: String
var display_name: String
var description: String

var trigger_event: TriggerEvent
var effect_type: EffectType
var effect_value: float        # multiplier or ratio; semantics depend on effect_type
var trigger_probability: float # 0.0–1.0; PASSIVE cards ignore this field

var cost: int                  # shop price
```

**Built-in card examples** (defined in `card_definitions.gd`):

| Card | Trigger | Prob | Effect |
|---|---|---|---|
| Critical Strike | ON_HIT | 20% | damage × 2 |
| Lifesteal | ON_HIT | 30% | heal 25% of damage dealt |
| Extra Damage | ON_HIT | 40% | +30% bonus damage |
| Dodge | ON_TAKE_HIT | 25% | negate all damage |
| Thorns | ON_TAKE_HIT | 100% | reflect 15% back to attacker |
| Speed Demon | PASSIVE | — | move_speed +20% |
| Regen Boost | PASSIVE | — | mp_regen +100% |

### HitResult

Returned by `CardProcessor.resolve_hit()`. Packages everything `SkillExecutor._apply_damage` needs after card resolution.

```gdscript
class_name HitResult extends RefCounted

var final_damage: int      # damage applied to target (0 if dodged)
var heal_amount: int       # HP restored to attacker (lifesteal)
var reflected_damage: int  # damage applied back to attacker (thorns)
var was_dodged: bool
var was_critical: bool
```

### CardProcessor

Stateless helper called exclusively on the referee. All `randf()` calls live here so RNG is server-authoritative.

```gdscript
class_name CardProcessor

static func resolve_hit(
    base_damage: int,
    attacker_cards: Array[CardData],
    target_cards: Array[CardData],
) -> HitResult:
    # 1. Apply ON_HIT cards (crit, lifesteal, extra damage)
    # 2. Apply ON_TAKE_HIT cards (dodge cancels damage; thorns add reflected)
    # Returns fully resolved HitResult

static func apply_passive_cards(character: CharacterBase, cards: Array[CardData]) -> void:
    # Called once per character at spawn.
    # Modifies move_speed, mp_regen, cooldown_reduction on CharacterBase.
```

### GameState

```gdscript
class_name GameState extends RefCounted

enum State { WAITING, PLAYING, ENDED }

var current_state: State = State.WAITING
var team1_alive: int = 3
var team2_alive: int = 3
var match_id: String
var players: Array[PlayerSession] = []
var winner_team: int = -1   # 1 or 2; -1 if not ended
```

### PlayerSession

```gdscript
class_name PlayerSession extends RefCounted

var player_id: String
var team_id: int                            # 1 or 2
var character_id: String
var equipped_card_ids: Array[String] = []   # Send IDs over the wire, not Resources
var is_connected: bool = true

# Stage 2 only — Nakama session token. Stays on client; never sent to referee.
var session_token: String
```

> **Security note:** `session_token` (Stage 2) authenticates the user to Nakama. It is never transmitted to the referee — the referee receives only `player_id` plus per-match credentials Nakama hands it directly.

## Network Flow

### Stage 1 — Direct ENet (current)

```
Player Client                       Referee
   │                                  │
   │── ENet connect to host:7777 ────▶│
   │◀── peer_connected ───────────────│
   │                                  │── _spawn_character(peer_id) (auth)
   │◀── MultiplayerSpawner replicate ─│
   │                                  │
   │── input RPC ────────────────────▶│
   │                                  │── validate, update authoritative state
   │◀── MultiplayerSynchronizer ──────│
   │                                  │
   │── skill RPC ────────────────────▶│
   │                                  │── hit detection, RNG roll, apply damage
   │◀── hit_result RPC (broadcast) ───│
   │                                  │
   │                                  │── victory check
   │◀── match_ended RPC ──────────────│
```

### Stage 2 — With Nakama Matchmaking

```
Client            Nakama            Referee
  │                 │                 │
  │── auth ────────▶│                 │
  │◀── token ───────│                 │
  │                 │                 │
  │── find match ──▶│                 │
  │                 │── allocate ────▶│
  │                 │◀── ready ───────│
  │◀─ referee addr ─│                 │
  │                 │                 │
  │── ENet connect (host:port from Nakama) ──────▶│
  │                                               │
  │  (gameplay proceeds exactly as Stage 1)       │
  │                                               │
  │── match_result ─▶│                            │
  │                  │◀── result report ──────────│
```

## Game Loop

```
1. MATCH START (referee)
   - Spawn 6 characters via MultiplayerSpawner
   - Assign teams + spawn positions
   - Initialize HP/MP/BP
   - Broadcast match_started

2. GAMEPLAY (per tick)
   ┌─ INPUT (client → referee)
   │   - Movement vector, skill activation
   │
   ├─ VALIDATION (referee)
   │   - Movement speed / dash availability
   │   - Resource availability (BP for dash, MP for ultimate)
   │   - Cooldown checks
   │   - Skill execution + hit detection
   │   - Card RNG rolls + damage application
   │   - Death checks
   │
   ├─ BROADCAST (referee → all clients)
   │   - Authoritative positions via MultiplayerSynchronizer
   │   - Combat results via RPC
   │   - Resource updates
   │
   └─ WIN CHECK
       - team1_alive == 0 → team 2 wins
       - team2_alive == 0 → team 1 wins

3. MATCH END
   - Broadcast winner
   - (Stage 2) report result to Nakama
   - Return clients to lobby
```

## HUD System

### Player HUD (minimal)

```
┌─────────────────────────────────────┐
│             [Timer]                 │
├─────────────────────────────────────┤
│                                     │
│          [Game Area]                │
│                                     │
├─────────────────────────────────────┤
│  [HP] ━━━━━━━━━━━━━━━━━━            │
│  [MP] ━━━━━━━  [BP] ━━━━━━━         │
│                                     │
│    [●] [●] [●]   ← Skill buttons    │
│         [Joystick]                  │
└─────────────────────────────────────┘
```

Components: timer, HP bar, MP bar, BP bar, three skill buttons (with cooldown overlay), virtual joystick.

### Referee HUD (debug only)

```
┌─────────────────────────────────────────────────┐
│ [Debug Panel]                                   │
│  - Network status (peers, RTT)                  │
│  - All 6 players' HP/MP/BP                      │
│  - Hitbox / hurtbox visualization               │
│  - Position coordinates                         │
│  - Match state                                  │
└─────────────────────────────────────────────────┘
```

## Input System

### PC (development)

| Action | Key |
|--------|-----|
| Move | WASD / Arrow keys |
| Skill 1 | J |
| Skill 2 | K |
| Ultimate | L |
| Dash | Double-tap movement key |

> WASD is reserved for movement. Skills bind to right-hand keys (JKL) so they don't conflict with movement input.

### Mobile

| Action | Input |
|--------|-------|
| Move | 360° virtual joystick |
| Skill 1 / 2 / Ult | Touch buttons (multi-touch supported) |
| Dash | Double-tap joystick direction |

### Joystick + Double-Tap Dash

```
JOYSTICK DRAG:
  - Move character in drag direction
  - Speed = move_speed × magnitude

DOUBLE TAP (within DOUBLE_TAP_TIME_WINDOW = 300ms):
  - Requires BP > 0
  - Activates dash mode: speed = move_speed × 2
  - BP drains at BP_DASH_DRAIN_PER_SEC while dashing
  - Dash ends when joystick is released OR BP reaches 0
  - BP regens at bp_regen/sec when not dashing
```

## Combat System

### Melee Attack
```
1. Player taps skill button
2. Client plays activation animation (predicted) + sends skill RPC
3. Referee validates: cooldown ready? in range?
4. Referee calculates damage (with card effect rolls)
5. Referee applies damage, broadcasts hit_result
6. Both clients play impact effect on confirmation
```

### Ranged Attack (Projectile)
```
1. Player taps skill button
2. Client plays cast animation (predicted) + sends skill RPC
3. Referee spawns projectile via MultiplayerSpawner
4. Projectile travels server-authoritatively
5. Referee detects collision
6. Referee applies damage, broadcasts hit_result + despawn
```

## Resource System

### HP (Health Points)
- Max defined per character (default 100)
- Death at HP ≤ 0
- No regen during match

### MP (Mana Points)
- Max 100, regen `DEFAULT_MP_REGEN`/sec
- Used by Ultimate skill only

### BP (Burst Points)
- Max 100, regen `DEFAULT_BP_REGEN`/sec when not dashing
- Used by dash; drains at `BP_DASH_DRAIN_PER_SEC` continuously while dashing
- Dash ends automatically when BP reaches 0 or joystick is released

## Victory Condition

```
Team 1 wins iff team2_alive == 0
Team 2 wins iff team1_alive == 0

When character HP ≤ 0:
  - Mark character dead (referee-authoritative)
  - Play death animation (predicted on client, confirmed on broadcast)
  - Decrement team_X_alive on referee
  - Broadcast updated counts
  - Run victory check
```

## Testing

### Unit Tests (GUT)

Place under `test/unit/`. Run with:

```bash
godot -d -s --path "$PWD" addons/gut/gut_cmdln.gd
```

### Manual Multi-Instance Test (current)

`test/manual/test_combat.gd` is the working multiplayer smoke test. It sets up ENet, `MultiplayerSpawner`, and demonstrates RPC across 3 Godot instances.

**Run via terminal:**
```
Instance 1 (Referee):  godot --path . -- --mode=referee
Instance 2 (Player A): godot --path .
Instance 3 (Player B): godot --path .
```

**Run via editor:**
1. Open `test/manual/test_combat.tscn`
2. **Run → Run Multiple Instances → 3**
3. **Editor Settings → Run → Main Run Args**: `--mode=referee` (only the first instance gets it)
4. Press F6

### Data Provider Abstraction (Stage 2 prep)

To run battles without Nakama, the player session source is abstracted behind `IPlayerDataProvider`. The same referee logic runs against either backend:

```
┌───────────────────────────────────────────┐
│              BATTLE TEST                  │
├───────────────────────────────────────────┤
│  ┌──────────┐                             │
│  │ Referee  │  ← same logic regardless    │
│  └────┬─────┘                             │
│       ▼                                   │
│  ┌──────────────────────────────────┐     │
│  │ IPlayerDataProvider              │     │
│  │  ┌──────────────┬──────────────┐ │     │
│  │  │ Nakama (S2)  │ Local mock   │ │     │
│  │  └──────────────┴──────────────┘ │     │
│  └──────────────────────────────────┘     │
│       ▼                                   │
│  ┌──────────┐         ┌──────────┐        │
│  │ Player A │         │ Player B │        │
│  └──────────┘         └──────────┘        │
└───────────────────────────────────────────┘
```

Local mock data:

```gdscript
# test/manual/test_battle_config.gd
class_name TestBattleConfig extends RefCounted

static func get_mock_sessions() -> Array[PlayerSession]:
    var sessions: Array[PlayerSession] = []

    var player_a := PlayerSession.new()
    player_a.player_id = "local_player_a"
    player_a.team_id = 1
    player_a.character_id = "warrior"
    sessions.append(player_a)

    var player_b := PlayerSession.new()
    player_b.player_id = "local_player_b"
    player_b.team_id = 2
    player_b.character_id = "mage"
    sessions.append(player_b)

    return sessions
```

## Implementation Roadmap

Bottom-up — each phase produces something playable that the next phase builds on. **Nakama is deferred until the local game works end-to-end.**

> Naming note: roadmap *Phases* below are independent of the Stage 1 / Stage 2 *network-stack* labels used earlier. Network Stage 2 begins at roadmap Phase 5.

### Phase 1 — Local Multiplayer Infrastructure (done)
- [x] ENet referee/client connection
- [x] `MultiplayerSpawner`-based character spawning
- [x] Basic RPC (request/broadcast)
- [x] Disconnect / cleanup handling (grace period + timeout forfeit)

### Phase 2 — Character & Movement
- [x] `CharacterBase` with HP/MP/BP
- [x] Joystick input
- [x] Dash (double-tap joystick, continuous BP drain, stops on release or BP=0)
- [x] MP/BP regen (referee-authoritative, synced via MultiplayerSynchronizer)
- [ ] Client-side movement prediction + server reconciliation
- [ ] Other-player position interpolation

### Phase 3 — Combat
- [x] Skill controller (skill_1, skill_2, ultimate)
- [x] Melee + AOE + projectile hit detection (referee-side)
- [x] HP / damage system
- [x] Cooldown system
- [x] Death + elimination logic

### Phase 4 — Match Lifecycle
- [ ] TDM mode (`tdm_manager.gd` implementing `IModeManager`)
- [ ] Victory check + match end flow
- [ ] Result screen
- [ ] Multiple characters (3–5)
- [ ] Card effects (referee-rolled RNG)

### Phase 5 — Nakama Integration (Network Stage 2 begins)
- [ ] Real auth + login screen
- [ ] Matchmaking flow (Nakama matchmaker → referee allocation)
- [ ] Card / shop persistence
- [ ] Account / progression

### Phase 6 — Polish
- [ ] Mobile UI tuning
- [ ] Performance profiling for mobile target
- [ ] Additional game modes (FFA, CTF, KOTH)
- [ ] (Optional) Lag compensation / rewind hit detection if playtesting demands
