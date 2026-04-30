# Arena Backend Architecture

## 왜 서비스가 두 개인가

| 역할 | Nakama | Python Orchestrator |
|---|---|---|
| 인증 / 계정 | O | X |
| 매칭큐 | O | X |
| 상점 / 덱 저장 | O | X |
| 매칭 완료 후 심판 할당 | X (프로세스 관리 불가) | **O** |
| Godot headless 프로세스 관리 | X | **O** |
| 포트 풀 관리 | X | **O** |
| 매치 결과 → Nakama 저장 | X (직접 수신 불가) | **O** (중계) |

Nakama는 Go 모듈 훅에서 HTTP로 Python 오케스트레이터를 호출한다. 게임 트래픽은 절대 Nakama를 거치지 않는다.

---

## 시스템 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                         CONTROL PLANE                       │
│                                                             │
│   ┌──────────────────┐   HTTP    ┌──────────────────────┐   │
│   │  NAKAMA SERVER   │ ────────▶ │  PYTHON ORCHESTRATOR │   │
│   │  (Go)            │ ◀──────── │  (FastAPI)           │   │
│   │  - Auth          │           │  - Referee 프로세스   │   │
│   │  - Matchmaking   │           │  - 포트 풀 관리       │   │
│   │  - Shop / 저장   │           │  - 헬스 모니터링      │   │
│   └────────┬─────────┘           └──────────┬───────────┘   │
│            │ WebSocket                       │ subprocess    │
│            │ (match_ready notification)      ▼               │
└────────────┼─────────────────────────────────────────────────┘
             │                        ┌─────────────────────┐
             │                        │  Godot Referee      │
             │                        │  (headless)         │
             │                        │  ENet :7800~:7899   │
             │                        └──────────┬──────────┘
             │                                   │ ENet (direct)
┌────────────┴───────────────────────────────────┴────────────┐
│                    CLIENT (Godot)                            │
│   1. Nakama로부터 referee endpoint 수신 (Notification)        │
│   2. ENet으로 referee에 직접 연결 (Nakama 무관)               │
└─────────────────────────────────────────────────────────────┘
```

---

## 전체 라이프사이클

### 1단계: 인증

```
Client → Nakama: authenticate (device ID 또는 custom token)
Nakama → Client: session_token
```

`session_token`은 이후 모든 Nakama API 호출에만 사용한다. referee에는 절대 전달하지 않는다.

### 2단계: 매칭큐 진입

```
Client → Nakama: MatchmakerAdd {
  min_count: 6,
  max_count: 6,
  query: "*",
  string_properties:  { game_mode: "tdm" },
  numeric_properties: { skill_rating: 1500.0 }
}
Nakama → Client: ticket (대기 중)
```

### 3단계: 매칭 완료 → 심판 할당

Nakama Go 모듈의 `RegisterMatchmakerMatched` 훅이 6명 매칭 완료 시 실행:

```go
// nakama/server/arena_module.go
func MatchmakerMatchedHandler(ctx, logger, db, nk, entries) (string, error) {
    playerIDs := extractPlayerIDs(entries)

    resp, err := http.Post("http://orchestrator:8080/allocate", "application/json", AllocateRequest{
        MatchID:   uuid.New().String(),
        PlayerIDs: playerIDs,
        GameMode:  "tdm",
    })
    // → { referee_host, referee_port, match_id }

    for _, entry := range entries {
        nk.NotificationSend(ctx, entry.Presence.GetUserId(), "match_ready", map[string]any{
            "referee_host": resp.RefereeHost,
            "referee_port": resp.RefereePort,
            "match_id":     resp.MatchID,
        }, ...)
    }
    return "", nil  // 외부 referee 사용; Nakama 내부 match 불필요
}
```

### 4단계: Python 오케스트레이터 — 심판 스폰

```python
# orchestrator/main.py
@app.post("/allocate")
async def allocate(req: AllocateRequest):
    port = await port_pool.acquire()   # 7800~7899 중 빈 포트
    match_id = req.match_id

    proc = await asyncio.create_subprocess_exec(
        GODOT_BIN, "--headless",
        "--path", GAME_PATH,
        "--",
        "--mode=referee",
        f"--match-id={match_id}",
        f"--port={port}",
        f"--orchestrator-url=http://orchestrator:8080",
    )

    await wait_for_ready(match_id, timeout=10)  # referee READY 신호 대기

    registry[match_id] = MatchRecord(proc=proc, port=port, player_ids=req.player_ids)
    return {"referee_host": PUBLIC_HOST, "referee_port": port, "match_id": match_id}
```

### 5단계: Godot 심판 — READY 보고

심판은 ENet 서버 바인딩 직후 오케스트레이터에 HTTP 신호를 보낸다:

```gdscript
# src/referee/referee_manager.gd
func _on_server_ready() -> void:
    var http := HTTPRequest.new()
    add_child(http)
    var body := JSON.stringify({"match_id": _match_id, "port": _port})
    http.request(
        "%s/match/%s/ready" % [_orchestrator_url, _match_id],
        ["Content-Type: application/json"],
        HTTPClient.METHOD_POST,
        body
    )
```

### 6단계: 클라이언트 → 심판 직접 연결

```gdscript
# src/network/match_manager.gd
func _on_match_ready_notification(data: Dictionary) -> void:
    var host: String = data["referee_host"]
    var port: int    = int(data["referee_port"])
    _match_id        = data["match_id"]
    _connect_to_referee(host, port)

func _connect_to_referee(host: String, port: int) -> void:
    var peer := ENetMultiplayerPeer.new()
    var err  := peer.create_client(host, port)
    assert(err == OK, "MatchManager: failed to create ENet client to %s:%d" % [host, port])
    multiplayer.multiplayer_peer = peer
```

### 7단계: 게임 진행 (Stage 1과 동일)

클라이언트 ↔ 심판 간 ENet 직접 통신. Nakama는 관여하지 않는다.

### 8단계: 매치 결과 저장

```
Referee → Orchestrator:
  POST /match/{match_id}/result {
    winner_team: 1,
    player_stats: [ { player_id, kills, deaths }, ... ]
  }

Orchestrator → Nakama Server-to-Server API:
  - WriteStorageObjects  →  match_result 저장
  - UpdateWallets        →  보상 재화 지급
  - UpdateLeaderboard    →  랭킹 업데이트

Orchestrator: 프로세스 종료, 포트 반납
```

---

## Nakama Go 모듈 — 구현 항목

**파일**: `nakama/server/arena_module.go` (신규)

```go
func InitModule(ctx, logger, db, nk, initializer) error {
    initializer.RegisterMatchmakerMatched(MatchmakerMatchedHandler)

    // 클라이언트용 RPC
    initializer.RegisterRpc("get_active_match", GetActiveMatchRpc)  // 재접속 시 referee 주소 재조회
    initializer.RegisterRpc("get_shop_items",   GetShopItemsRpc)
    initializer.RegisterRpc("purchase_item",    PurchaseItemRpc)
    initializer.RegisterRpc("save_deck",        SaveDeckRpc)
    initializer.RegisterRpc("get_deck",         GetDeckRpc)

    // 최초 가입 시 초기 재화 지급
    initializer.RegisterAfterAuthenticateDevice(OnFirstLogin)

    return nil
}
```

### Nakama Storage 스키마

| Collection | Key | Value |
|---|---|---|
| `player_profile` | `{user_id}` | `display_name`, `level`, `currency` |
| `deck` | `{user_id}` | `equipped_card_ids: Array[String]` |
| `match_result` | `{match_id}` | `winner_team`, `player_stats`, `timestamp` |
| `shop_catalog` | `global` | 판매 중인 카드 목록 |

---

## Python 오케스트레이터 — 서비스 설계

### 기술 스택

| 라이브러리 | 용도 |
|---|---|
| FastAPI + uvicorn | REST API 서버 |
| asyncio.subprocess | Godot 프로세스 스폰 / 종료 |
| httpx | Nakama server-to-server API 호출 |
| Redis (선택) | 분산 배포 시 match registry 공유 |

### API 엔드포인트

```
POST /allocate
  Body:    { match_id, player_ids, game_mode }
  Returns: { referee_host, referee_port, match_id }
  Errors:  503 포트 고갈 | 504 referee 시작 타임아웃

POST /match/{match_id}/ready
  Body: { port }
  referee → orchestrator: ENet 서버 준비 완료 신호

POST /match/{match_id}/result
  Body: { winner_team, player_stats }
  referee → orchestrator: 게임 종료 결과 보고

GET  /match/{match_id}
  Returns: { status, referee_host, referee_port, player_ids, started_at }

GET  /health
  Returns: { active_matches, available_ports }
```

### 포트 풀 관리

```python
class PortPool:
    def __init__(self, start: int = 7800, end: int = 7900):
        self._free = set(range(start, end))
        self._lock = asyncio.Lock()

    async def acquire(self) -> int:
        async with self._lock:
            if not self._free:
                raise HTTPException(503, "No available referee ports")
            return self._free.pop()

    async def release(self, port: int) -> None:
        async with self._lock:
            self._free.add(port)
```

### 헬스 모니터링

- 30초 간격으로 모든 active match 프로세스 상태 확인
- referee가 예상치 않게 종료되면 → Nakama에 `match_aborted` 알림 전송
- 매치 최대 시간(20분) 초과 시 강제 종료 후 draw 처리

### 환경 변수

```
GODOT_BIN           = /usr/local/bin/godot
GAME_PATH           = /app/arena
PUBLIC_HOST         = game.arena.example.com
NAKAMA_URL          = http://nakama:7350
NAKAMA_SERVER_KEY   = defaultkey
PORT_RANGE_START    = 7800
PORT_RANGE_END      = 7900
ALLOCATE_TIMEOUT_S  = 10
MATCH_MAX_DURATION_S = 1200
```

---

## Godot 변경 사항

### Client (Player Mode)

| 파일 | 변경 내용 |
|---|---|
| `src/network/nakama_client.gd` | Nakama SDK 초기화, session_token 관리, 실시간 소켓 연결 |
| `src/network/match_manager.gd` | `match_ready` Notification 수신 → referee ENet 연결 |
| `src/screen/login_screen.gd` | 기기 ID / 커스텀 토큰 로그인 |
| `src/screen/lobby_screen.gd` | 매칭큐 진입 / 취소 UI |
| `src/screen/character_select_screen.gd` | 캐릭터 선택 결과를 Nakama에 저장 |

### Referee (--mode=referee)

| 파일 | 변경 내용 |
|---|---|
| `src/referee/referee_manager.gd` | `--port`, `--match-id`, `--orchestrator-url` cmdline 파싱 |
| `src/referee/referee_manager.gd` | ENet 서버 시작 후 `POST /match/{id}/ready` 호출 |
| `src/referee/referee_manager.gd` | 게임 종료 시 `POST /match/{id}/result` 호출 |

### 심판 커맨드라인 인자

```gdscript
# src/referee/referee_manager.gd
func _parse_args() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--match-id="):
            _match_id = arg.split("=")[1]
        elif arg.begins_with("--port="):
            _port = arg.split("=")[1].to_int()
        elif arg.begins_with("--orchestrator-url="):
            _orchestrator_url = arg.split("=")[1]
    assert(_match_id != "", "referee: --match-id required")
    assert(_port > 0,       "referee: --port required")
```

---

## 배포 구조

### docker-compose.yml (전체 스택)

```yaml
services:
  cockroachdb:
    # (기존 설정 유지)

  nakama:
    # (기존 설정 유지) 포트 7349/7350/7351

  orchestrator:
    build: ./orchestrator
    ports:
      - "8080:8080"
      - "7800-7900:7800-7900"   # referee ENet 포트 범위
    volumes:
      - ./godot_bin:/usr/local/bin/godot   # Godot 바이너리 마운트
      - ./arena_export:/app/arena          # 게임 export 마운트
    environment:
      - NAKAMA_URL=http://nakama:7350
      - PUBLIC_HOST=localhost
    depends_on:
      - nakama
```

### 프로덕션 고려사항

| 항목 | 초기 | 스케일아웃 시 |
|---|---|---|
| orchestrator | 1대 (단일 서버) | 여러 대 + Redis match registry |
| referee 프로세스 | 100개 (포트 7800~7899) | 서버 증설 또는 k8s Pod |
| referee 스폰 방식 | subprocess | k8s Job API (orchestrator가 직접 호출) |
| 방화벽 | 7800~7900 UDP+TCP 오픈 필요 | 동일 |

---

## 구현 순서

### Sprint 1 — 오케스트레이터 기본 뼈대
1. `orchestrator/` FastAPI 프로젝트 초기화
2. `/allocate`, `/match/{id}/ready`, `/match/{id}/result` 구현
3. Godot 프로세스 스폰 + 포트 풀 관리
4. `docker-compose.yml`에 orchestrator 서비스 추가

### Sprint 2 — Nakama Go 모듈
1. `nakama/server/arena_module.go` 생성
2. `RegisterMatchmakerMatched` → orchestrator HTTP 호출
3. 결과를 Nakama Notification으로 클라이언트에 전달
4. Storage 스키마 정의 (profile, deck, match_result)

### Sprint 3 — Godot 심판 연동 ✅
1. `referee_manager.gd` — `--port`, `--match-id`, `--orchestrator-url` 인자 파싱 완료
2. ENet 서버 바인딩 후 `POST /match/{id}/ready` 자동 호출
3. 게임 종료 시 `POST /match/{id}/result` 자동 호출
4. `gserver/main.py` — 로컬 테스트용 FastAPI 오케스트레이터 구현 완료

### Sprint 4 — Godot 클라이언트 연동
1. `nakama_client.gd` — SDK 초기화, 로그인, 실시간 소켓
2. `match_manager.gd` — 매칭큐 + Notification 수신 + referee ENet 연결
3. `lobby_screen.gd` — 실제 매칭 UI

### Sprint 5 — 상점 / 덱 / 진행도
1. Shop RPC 구현 (Nakama)
2. Deck 저장/불러오기
3. 매치 결과 → 보상 지급 파이프라인

---

## 미결 사항

| 항목 | 현재 결정 | 재검토 시점 |
|---|---|---|
| referee 재접속 지원 | `get_active_match` RPC로 referee 주소 재조회 | Sprint 4 |
| referee 클라이언트 인증 | player_id만 사용 (session_token 미전달) | Sprint 3 |
| 포트 고갈 시 처리 | 503 반환 → 매칭 큐 재진입 유도 | Sprint 1 |
| k8s 스케일아웃 | 단일 서버로 시작 | 플레이테스트 후 |
| referee 비정상 종료 | orchestrator 감지 → draw 처리 + 알림 | Sprint 3 |
| referee ↔ Nakama 직접 통신 | orchestrator 중계 방식 유지 | Sprint 5 |
