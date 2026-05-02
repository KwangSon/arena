# Battle Test Guide

Two ways to test multiplayer combat locally.
Supports both **1v1** and **3v3 Team Deathmatch** modes.

---

## Method 1 — Referee in Terminal, Clients in Godot Editor (Local Debug)

Run the referee from the terminal and launch client instances from the Godot editor.
This keeps the referee output visible in the terminal while the clients run as editor instances.

### 1v1 (test_combat.tscn)

#### Terminal

```bash
cd arena
arena$ ./godot --path "$PWD" test/manual/test_combat.tscn -- --mode=referee
```

#### Godot Editor

1. Open scene `test/manual/test_combat.tscn`
2. Top ▶ button dropdown → **Run Multiple Instances → 2**
3. Leave **Editor Settings → Run → Main Run Args** empty for client instances
4. Press **F6**

### 3v3 Team Deathmatch (test_tdm.tscn)

#### Terminal

```bash
cd arena
arena$ ./godot --path "$PWD" test/manual/test_tdm.tscn -- --mode=referee --game-mode=3v3
```

#### Godot Editor

1. Open scene `test/manual/test_tdm.tscn`
2. Top ▶ button dropdown → **Run Multiple Instances → 6**
3. Leave **Editor Settings → Run → Main Run Args** empty for client instances
4. Press **F6**

> The referee is always started separately in the terminal. The editor runs only the client instances.

### Characteristics

| | |
|---|---|
| Pros | No FastAPI needed, fast iteration, referee logs visible in terminal |
| Cons | All local, no mobile access |
| Port | 7777 (hardcoded) |

---

## Method 2 — FastAPI Orchestrator (Real Network)

FastAPI (gserver) automatically spawns the referee process.
The referee runs headless in the background, and clients on the same LAN —
including other PCs or mobile devices — can connect.

### Launch Order

**Step 1 — Start gserver**

```bash
cd gserver
gserver$ GAME_PATH="$PWD/.." uv run main.py
```

> Uses the `godot` symlink inside `GAME_PATH` to spawn the referee.

**Step 2 — Launch clients**

Use the Godot editor to launch client instances locally.

For local editor testing:
1. Open `src/main.tscn` or the lobby scene in Godot editor.
2. Run client instances from the editor.

For other PC / mobile devices:
- Open the exported client or mobile build.

**Step 3 — Start match from lobby**

Click **1:1 매치** or **3:3 매치** in the lobby screen. The gserver will:

- Queue players per game mode (1v1 and 3v3 queues are independent)
- Spawn a referee process with `--game-mode=1v1` or `--game-mode=3v3`
- 1v1: fires when 2 players queue
- 3v3: fires when 6 players queue

**Automatic flow (1v1):**

```
Client A "1:1 매치" → POST /queue {"player_id":..., "game_mode":"1v1"}
Client B "1:1 매치" → POST /queue {"player_id":..., "game_mode":"1v1"}
                       ↓ 2 players queued
gserver → godot --headless ... -- --mode=referee --game-mode=1v1 --port=7800 ...
Referee → POST /match/{id}/ready
Clients ← GET /queue/{player_id}/status → matched
Clients → ENet connect to localhost:7800
```

**Automatic flow (3v3):**

```
6 Clients "3:3 매치" → POST /queue {"player_id":..., "game_mode":"3v3"}
                        ↓ 6 players queued
gserver → godot --headless ... -- --mode=referee --game-mode=3v3 --port=7801 ...
Referee → POST /match/{id}/ready
Clients ← GET /queue/{player_id}/status → matched
Clients → ENet connect to localhost:7801
```

### Mobile / Other PC Access

Set the `PUBLIC_HOST` environment variable to the server's LAN IP.

```bash
PUBLIC_HOST=192.168.1.100 GAME_PATH="$PWD/.." uv run main.py
```

Clients (including mobile) must set the **Server IP** field in the lobby screen to that IP.

### Characteristics

| | |
|---|---|
| Pros | Real network environment, mobile access, referee auto-spawned and cleaned up |
| Cons | Requires gserver running, referee logs mixed into gserver terminal |
| Port | 8080 (gserver HTTP), 7800–7899 (referee ENet, auto-assigned) |

---

## 3v3 Team Deathmatch — Test Checklist

| # | Test | Expected |
|---|---|---|
| 1 | 6명 접속 | Team 1 (BLUE): 3명, Team 2 (RED): 3명 |
| 2 | Team 2의 1명 사망 | 매치 계속 (alive: {1:3, 2:2}) |
| 3 | Team 2의 나머지 2명 사망 | 매치 종료, Team 1 승리 |
| 4 | AOE 스킬 사용 | 아군은 피격되지 않음 |
| 5 | 1명 Force Disconnect | 10초 후 해당 플레이어만 제거, 매치 계속 |
| 6 | 한 팀 3명 모두 Disconnect | 타임아웃 후 매치 종료, 상대팀 승리 |

---

## Environment Variables (gserver)

| Variable | Default | Description |
|---|---|---|
| `GAME_PATH` | `.` | Godot project path |
| `GODOT_BIN` | `{GAME_PATH}/godot` | Godot executable path |
| `PUBLIC_HOST` | `localhost` | Referee address reported to clients |
| `PORT_RANGE_START` | `7800` | Start of referee ENet port range |
| `PORT_RANGE_END` | `7900` | End of referee ENet port range |
| `ALLOCATE_TIMEOUT_S` | `10` | Timeout in seconds waiting for referee ready |
