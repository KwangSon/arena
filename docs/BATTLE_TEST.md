# Battle Test Guide

Two ways to test multiplayer combat locally.

---

## Method 1 — Referee in Terminal, Clients in Godot Editor (Local Debug)

Run the referee from the terminal and launch the two client instances from the Godot editor.
This keeps the referee output visible in the terminal while the clients run as editor instances.

### Terminal

```bash
cd arena
arena$ ./godot --path "$PWD" test/manual/test_combat.tscn -- --mode=referee
```

### Godot Editor

1. Open scene `test/manual/test_combat.tscn`
2. Top ▶ button dropdown → **Run Multiple Instances → 2**
3. Leave **Editor Settings → Run → Main Run Args** empty for client instances
4. Press **F6**

> The referee is always started separately in the terminal. The editor runs only the two client instances.

### Characteristics

| | |
|---|---|
| Pros | No FastAPI needed, fast iteration, referee logs visible in Godot console |
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
cd arena/gserver
arena$ GAME_PATH="$PWD/.." uv run main.py
```

> Uses the `godot` symlink inside `GAME_PATH` to spawn the referee.

**Step 2 — Launch 2 clients**

Use the Godot editor to launch the two client instances locally.

```bash
cd /Users/kwang/Documents/git-repos/arena
arena$ # Open Godot editor, load the project, and run the client scene
```

For local editor testing:
1. Open `src/main.tscn` or the lobby scene in Godot editor.
2. Run two client instances from the editor.

For other PC / mobile devices:
- Open the exported client or mobile build and click **Start Match** in the lobby screen.

**Automatic flow:**

```
Client A "Start Match" → POST /queue
Client B "Start Match" → POST /queue
                          ↓ 2 players queued
gserver → godot --headless --path ... -- --mode=referee --port=7800 --match-id=...
Referee → POST /match/{id}/ready
Clients ← GET /queue/{player_id}/status → matched
Clients → ENet connect to localhost:7800
```

### Mobile / Other PC Access

Set the `PUBLIC_HOST` environment variable to the server's LAN IP.

```bash
PUBLIC_HOST=192.168.1.100 GAME_PATH=/path/to/arena uv run main.py
```

Clients (including mobile) must update `GSERVER_URL` in the lobby screen to that IP.
It is currently defined as a constant at the top of `src/screen/lobby_screen.gd`:

```gdscript
const GSERVER_URL: String = "http://192.168.1.100:8080"
```

### Characteristics

| | |
|---|---|
| Pros | Real network environment, mobile access, referee auto-spawned and cleaned up |
| Cons | Requires gserver running, referee logs mixed into gserver terminal |
| Port | 8080 (gserver HTTP), 7800–7899 (referee ENet, auto-assigned) |

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
