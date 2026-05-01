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

Godot's high-level multiplayer over ENet. The referee instance creates an ENet server; player instances connect as clients.

Two ways to run a match locally — see `docs/BATTLE_TEST.md` for details:

| Method | How | Port |
|---|---|---|
| 3 editor instances | Editor "Run Multiple Instances → 3", first gets `--mode=referee` | 7777 |
| gserver (FastAPI) | `GAME_PATH=... uv run gserver/main.py` spawns referee headless; clients connect via lobby | 8080 (HTTP), 7800–7899 (ENet) |

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
├── gserver/                       # Local FastAPI orchestrator (dev/testing)
│   └── main.py                    # HTTP server that spawns referee processes
│
├── src/
│   ├── main.gd                    # Entry point — referee vs player mode dispatch
│   ├── main.tscn                  # Minimal main scene
│   │
│   ├── global/                    # Autoloads
│   │   └── screen_manager.gd      # Screen lifecycle manager + game_ready signal
│   │
│   ├── screen/                    # UI screens (Player mode only)
│   │   ├── lobby_screen.gd        # Matchmaking queue UI (gserver HTTP polling)
│   │   ├── result_screen.gd       # Post-match result + return-to-lobby
│   │   ├── game_screen.gd         # (planned)
│   │   ├── login_screen.gd        # (planned — Stage 2 Nakama)
│   │   ├── shop_screen.gd         # (planned)
│   │   └── character_select_screen.gd  # (planned)
│   │
│   ├── game/
│   │   └── match_session.gd       # Network layer + RPCs (referee & client share same path)
│   │
│   ├── referee/
│   │   └── referee_manager.gd     # Referee-only game logic (child of MatchSession)
│   │
│   ├── character/
│   │   ├── character_base.gd      # CharacterBody2D with HP/MP/BP + movement
│   │   ├── character_base.tscn    # Minimal scene for character_base.gd
│   │   └── character_spawner.gd   # Static helpers: create_node() + MultiplayerSynchronizer setup
│   │
│   ├── combat/
│   │   ├── skill_executor.gd      # Referee-side skill execution + hit detection
│   │   ├── projectile.gd          # Projectile node (spawned via MultiplayerSpawner)
│   │   └── projectile.tscn        # Minimal scene for projectile.gd
│   │
│   ├── input/
│   │   └── dash_detector.gd       # Double-tap dash detection (client-side)
│   │
│   ├── data/                      # Code-based data definitions (no .tres files)
│   │   ├── character_data.gd      # CharacterData class
│   │   ├── character_definitions.gd  # CharacterDefinitions.create(id) factory
│   │   ├── skill_data.gd          # SkillData class
│   │   ├── card_data.gd           # CardData class (slot-based equipment)
│   │   └── card_definitions.gd    # CardDefinitions static factory
│   │
│   └── ui/
│       ├── player_hud.gd          # In-game HUD (MP/BP bars, skill buttons, joystick)
│       └── player_hud.tscn
│
└── test/
    ├── unit/                      # GUT unit tests
    │   ├── test_card_effects.gd
    │   ├── test_character_spawner.gd
    │   ├── test_dash_detector.gd
    │   ├── test_referee_movement.gd
    │   └── test_skill_executor.gd
    └── manual/                    # Multi-instance manual tests
        ├── test_combat.gd         # Thin wrapper around MatchSession + ping/disconnect debug UI
        └── test_combat.tscn
```

> `CharacterData` lives at `src/data/character_data.gd` only. `src/character/` holds runtime character classes (`character_base.gd`), not data definitions.

## Core Data Types

Mode detection is done inline at startup — no autoload needed:

```gdscript
var _is_referee: bool = "--mode=referee" in OS.get_cmdline_user_args()
```

### CharacterData

```gdscript
class_name CharacterData

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

# Visuals
var sprite_frames: SpriteFrames = null
var default_animation: String = "idle_down"
```

> All instances are constructed in code (`character_definitions.gd`). No `.tres` files, no `@export` annotations.

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

Cards are slot-based equipment applied at character spawn. Each slot has a fixed stat modifier role.

```gdscript
class_name CardData extends Resource

enum Slot { MAIN_WEAPON, SUB_WEAPON, ARMOR, SHOES, ULTIMATE }

var id: String
var display_name: String
var slot: Slot

var damage_mult: float = 1.0       # MAIN_WEAPON / SUB_WEAPON
var cooldown_mult: float = 1.0     # MAIN_WEAPON / ULTIMATE
var max_hp_bonus: int = 0          # ARMOR
var damage_reduction: float = 0.0  # ARMOR
var move_speed_mult: float = 1.0   # SHOES
var bp_regen_mult: float = 1.0     # SHOES
var mp_cost_mult: float = 1.0      # ULTIMATE
```

**Built-in cards** (defined in `card_definitions.gd`):

| Card | Slot | Effect |
|---|---|---|
| 강화 주무기 | MAIN_WEAPON | damage ×1.2, cooldown ×0.85 |
| 강화 보조무기 | SUB_WEAPON | damage ×1.2, cooldown ×0.85 |
| 방어 갑옷 | ARMOR | +20 max HP, 15% damage reduction |
| 질주 신발 | SHOES | move_speed ×1.2, bp_regen ×1.5 |
| 강화 궁극기 | ULTIMATE | cooldown ×0.8, mp_cost ×0.85 |

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

### Phase 1 — Local Multiplayer Infrastructure ✅
- [x] ENet referee/client connection
- [x] `MultiplayerSpawner`-based character spawning
- [x] Basic RPC (request/broadcast)
- [x] Disconnect / cleanup handling (grace period + timeout forfeit)
- [x] FastAPI gserver — local orchestrator for referee process spawning

### Phase 2 — Character & Movement ✅ (core done)
- [x] `CharacterBase` with HP/MP/BP
- [x] Joystick input
- [x] Dash (double-tap joystick, continuous BP drain, stops on release or BP=0)
- [x] MP/BP regen (referee-authoritative, synced via MultiplayerSynchronizer)
- [x] Card equipment system (slot-based: weapon/armor/shoes/ultimate)
- [ ] Client-side movement prediction + server reconciliation
- [ ] Other-player position interpolation

### Phase 4 — Match Lifecycle (in progress)
- [x] Match end broadcast (`broadcast_match_ended` RPC)
- [x] Result screen + return-to-lobby flow
- [x] Card effects applied to damage (damage_mult, damage_reduction, etc.)
- [ ] TDM proper: 3v3 team victory condition
- [ ] Multiple characters (currently knight/mage only)


## Backend Architecture & Phased Strategy

### Phased Strategy
The backend is expanded in phases. Each phase can operate independently, progressing to the next only after the previous is complete.

| Stage | Nakama Role | Matchmaking / Orchestration | Status |
|-------|------------|-------------------|------|
| **Stage 0** | None | gserver (Local FastAPI) | ✅ Current |
| **Stage 1** | Auth + Storage + Leaderboard (Minimal) | gserver | Next |
| **Stage 2** | Expanded with Matchmaking | Go module or gserver (TBD) | TBD |

> **Core Principle**: Game traffic (ENet) NEVER goes through Nakama. Nakama is strictly for the control plane.

### Stage 0 — gserver Only (Current) ✅
Without Nakama, `gserver` (FastAPI) handles both matchmaking and referee process management.
- Clients `POST` to `/queue` to start a match.
- `gserver` spawns a headless referee process.
- Referee `POST`s to `/match/{id}/ready` when initialized.
- Clients poll `/queue/{player_id}/status` and connect directly to the referee via ENet.

### Stage 1 — Minimal Nakama Integration (Next)
Nakama is introduced minimally for three purposes:
1. **Authentication**: Automatic Device ID login (no account UI).
2. **Persistent Storage**: Gold, owned cards, and equipped decks.
3. **Leaderboards**: Season win counts.

Matchmaking, relay, chat, social features, and custom Go modules are NOT used yet. Matchmaking and referee allocation remain with `gserver`.

#### Mock vs Real Mode
If `nakama/ip` is empty in `project.godot`, the game runs in **Mock Mode** (no Nakama server needed).

#### Screen Flow Changes
- **Previous**: `main.gd` → `LOBBY`
- **New**: `main.gd` → `LOGIN` → `LOBBY`
The `LoginScreen` proceeds automatically in `_ready()` with no user input required.

#### Role Distribution
| Feature | Responsible Component |
|---------|------------------------|
| Device Auth | `NakamaService.login_async()` |
| Profile/Deck Storage R/W | `NakamaService` (Nakama Storage) |
| Card Purchase | `PlayerData.buy_card()` (Local, gold validation trusted on client) |
| Leaderboard Query | `NakamaService.get_leaderboard_async()` |
| **Post-Match Leaderboard Update** | **gserver** (Server-to-Server via Nakama HTTP API) |
| Matchmaking & Referee Allocation | **gserver** (Same as Stage 0) |

#### Nakama Storage Schema
| Collection | Key | Value |
|---|---|---|
| `player` | `profile` | `{"gold": 2000, "owned_card_ids": ["armor"]}` |
| `player` | `deck` | `{"equipped": {"2": "armor", "3": "shoes"}}` |

- **Leaderboard ID**: `season_wins` (DESCENDING, BEST)

### Stage 2 — Matchmaking Expansion (TBD)
To be decided after Stage 1. Two options exist:

#### Option A: Nakama Go Module
Use Nakama's `RegisterMatchmakerMatched` hook. The Go module requests referee allocation from the orchestrator.
- **Pros**: Utilizes Nakama's matchmaking infrastructure (skill rating, queue management).
- **Cons**: Increased complexity in developing and deploying Go modules.

#### Option B: gserver Expansion
`gserver` implements the matchmaking logic directly.
- **Pros**: Single Python stack, simple deployment.
- **Cons**: Requires custom implementation of matchmaking (skill rating, timeouts, etc.).

### Python Orchestrator Service Design (`gserver`)
The orchestrator manages referee processes across all stages.
- **Stack**: FastAPI + uvicorn, `asyncio.subprocess` (for Godot processes), `httpx` (for Nakama API).
- **Port Pool Management**: Assigns available UDP/TCP ports (e.g., 7800-7900) to new referee instances.
- **Health Monitoring**: Checks active match processes every 30 seconds. Terminates matches if the referee crashes or exceeds the maximum duration (20 mins).

#### Deployment Structure (Stage 2)
In production, the orchestrator and Nakama run via `docker-compose`. The orchestrator mounts the Godot binary and game export, exposing the required ports for ENet connections.

#### Open Issues
- **Stage 2 Matchmaking Approach**: TBD (Go module vs gserver).
- **Referee Reconnection**: To be supported in Stage 2 via a `get_active_match` RPC.
- **Kubernetes Scale-out**: Start with a single server, evaluate after playtests.

### 📌 Remaining Tasks & Backlog (What's Left)

#### 1. Core Gameplay & Network Polish (Phase 2 & 4)
- **Client-Side Prediction & Reconciliation**: Implement smooth movement for the local player to hide input latency.
- **Position Interpolation**: Render other players slightly behind the authoritative state to prevent visual jittering on the network.
- **3v3 TDM Logic**: Ensure the referee correctly tracks `team1_alive` and `team2_alive` and broadcasts victory only when an entire team is eliminated.
- **Character Expansion**: Add more character definitions and assets beyond `knight` and `mage`.

#### 2. Network Stage 2 (Nakama Integration - Phase 5)
- **Authentication**: Connect the Login screen to Nakama to issue real user session tokens.
- **Matchmaking Flow**: Replace the manual FastAPI `gserver` orchestrator with Nakama Matchmaker to dynamically allocate players to referee instances.
- **Persistence**: Store player data, owned cards, equipped decks, and shop purchases in Nakama Storage.

#### 3. UX & Polish (Phase 6)
- **Mobile UI Tuning**: Adjust virtual joystick, skill buttons, and HUD for actual mobile device dimensions and touch interactions.
- **Performance Profiling**: Optimize code and assets to ensure 60fps on target mobile devices.
- **Additional Game Modes**: Introduce Free-For-All (FFA), Capture The Flag (CTF), or King of the Hill (KOTH).
- *(Optional)* **Lag Compensation**: Consider server-side rewind for hit detection if playtesting on mobile networks demands it.
