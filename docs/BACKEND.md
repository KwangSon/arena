# Arena Backend Architecture

## 단계별 전략

백엔드는 단계적으로 확장한다. 각 단계는 독립적으로 동작 가능하며, 이전 단계가 완성된 후 다음 단계로 진행한다.

| 단계 | Nakama 역할 | 매칭/오케스트레이션 | 상태 |
|------|------------|-------------------|------|
| **Stage 0** | 없음 | gserver (로컬 FastAPI) | ✅ 현재 |
| **Stage 1** | 인증 + 저장 + 랭킹 (최소한) | gserver | 다음 |
| **Stage 2** | 매칭메이킹 포함 확장 | Go 모듈 or gserver (TBD) | 미정 |

> **핵심 원칙**: 게임 트래픽(ENet)은 절대 Nakama를 거치지 않는다. Nakama는 control plane 전용.

---

## Stage 0 — gserver만 (현재) ✅

Nakama 없이 gserver(FastAPI)가 매칭 + 심판 프로세스 관리를 모두 처리.

```
Client A "Start Match" → POST /queue
Client B "Start Match" → POST /queue
                          ↓ 2 players queued
gserver → godot --headless -- --mode=referee --port=7800 --match-id=...
Referee → POST /match/{id}/ready
Clients ← GET /queue/{player_id}/status → matched
Clients → ENet connect to localhost:7800
```

> 상세 테스트 방법은 `docs/BATTLE_TEST.md` 참조.

---

## Stage 1 — Nakama 최소 도입 (다음)

Nakama를 **최소한**으로 사용하여 아래 3가지만 처리한다.

1. **인증** — Device ID 자동 로그인 (계정 UI 없음)
2. **영속 저장** — 골드 + 보유카드 + 덱
3. **랭킹** — 시즌 승리수

Nakama 매치메이킹·릴레이·채팅·소셜·Go 커스텀 모듈은 사용하지 않는다.
매칭과 심판 할당은 Stage 0의 gserver가 계속 담당한다.

### Mock vs Real Mode

`project.godot`의 `nakama/ip`가 비어있으면 → **Mock Mode** (Nakama 서버 없이 전체 동작).

### 화면 흐름 변경

```
기존: main.gd → LOBBY
변경: main.gd → LOGIN → LOBBY
```

LoginScreen은 버튼 없이 `_ready()`에서 자동 진행. 사용자 입력 없음.

| 모드 | 동작 |
|------|------|
| Mock | Nakama 통신 없이 즉시 `login_complete` 발생 |
| Real | `authenticate_device_async(OS.get_unique_id())` → 완료되면 `login_complete` 발생 |

### 역할 분담

| 기능 | 담당 |
|------|------|
| Device 인증 | NakamaService.login_async() |
| 프로필/덱 저장·불러오기 | NakamaService — Nakama Storage R/W |
| 카드 구매 | PlayerData.buy_card() (로컬, 골드 검증 클라이언트 신뢰) |
| 랭킹 조회 | NakamaService.get_leaderboard_async() |
| **매치 후 랭킹 기록** | **gserver** — Nakama HTTP API 서버-투-서버 |
| 매칭 + 심판 할당 | **gserver** (Stage 0과 동일) |

### NakamaService API

```gdscript
# src/global/nakama_service.gd

## Mock: 즉시 true / Real: authenticate_device_async(OS.get_unique_id())
func login_async() -> bool

## 로그인 직후 1회 — StorageRead profile/deck → PlayerData 반영 (없으면 초기값 생성)
func load_profile_async() -> void

## 로비 복귀 시 — 현재 덱을 StorageWrite / Mock: no-op
func save_deck_async() -> void

## 랭킹 팝업용 / Mock: []
func get_leaderboard_async(limit: int = 10) -> Array
```

### Nakama Storage 스키마

| Collection | Key | Value |
|---|---|---|
| `player` | `profile` | `{"gold": 2000, "owned_card_ids": ["armor"]}` |
| `player` | `deck` | `{"equipped": {"2": "armor", "3": "shoes"}}` |

Leaderboard ID: `season_wins` (DESCENDING, BEST)

### 신규/수정 파일

**신규:**

| 파일 | 역할 |
|------|------|
| `src/global/nakama_service.gd` | Autoload — 인증·저장·랭킹 단일 창구 |
| `src/screen/login_screen.gd` | 자동 로그인 진입 화면 (스피너만 표시) |

**수정:**

| 파일 | 변경 내용 |
|------|----------|
| `src/global/screen_manager.gd` | `LOGIN` 화면 추가, 로비 복귀 시 `save_deck_async()` 호출 |
| `src/main.gd` | 시작 화면을 `LOGIN`으로 변경 |
| `src/global/player_data.gd` | `get_equipped_dict()`, `load_deck()` 메서드 추가 |
| `src/screen/lobby_screen.gd` | 랭킹 버튼 추가 |
| `gserver/main.py` | 매치 결과 후 Nakama 랭킹 기록 (`NAKAMA_URL` env 설정 시만) |
| `project.godot` | `NakamaService` autoload 등록 |

### gserver 랭킹 연동

```
환경변수: NAKAMA_URL, NAKAMA_HTTP_KEY
없으면 스킵 → Mock 환경 영향 없음
```

### 구현 순서

1. `nakama_service.gd` Autoload 생성 (Mock/Real 분기)
2. `login_screen.gd` → 자동 인증 → Lobby 전환
3. 프로필/덱 저장·불러오기
4. 랭킹 조회 UI
5. gserver에 Nakama 랭킹 기록 연동

---

## Stage 2 — 매칭메이킹 확장 (미정)

Stage 1 완성 후 결정. 두 가지 옵션:

### 옵션 A: Nakama Go 모듈

Nakama의 `RegisterMatchmakerMatched` 훅으로 매칭 → Go 모듈이 orchestrator에 심판 할당 요청.

- 장점: Nakama의 매칭메이킹 인프라(스킬 레이팅, 큐 관리) 활용
- 단점: Go 모듈 개발/배포 복잡도 증가

### 옵션 B: gserver 확장

gserver가 직접 매칭메이킹 로직을 구현.

- 장점: Python 단일 스택, 배포 단순
- 단점: 매칭메이킹 직접 구현 필요 (스킬 레이팅, 큐 타임아웃 등)

### 시스템 구성도 (Stage 2 — 옵션 A의 경우)

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

### 전체 라이프사이클 (옵션 A)

**1단계: 인증**

```
Client → Nakama: authenticate (device ID 또는 custom token)
Nakama → Client: session_token
```

`session_token`은 이후 모든 Nakama API 호출에만 사용한다. referee에는 절대 전달하지 않는다.

**2단계: 매칭큐 진입**

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

**3단계: 매칭 완료 → 심판 할당**

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

**4단계: 심판 스폰 (orchestrator)**

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

**5~8단계**: referee READY 보고 → 클라이언트 직접 연결 → 게임 진행 → 매치 결과 저장 (Stage 0과 동일 패턴)

### Nakama Go 모듈 — 구현 항목 (옵션 A)

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

### Nakama Storage 스키마 (옵션 A 확장)

Stage 1 스키마에 추가:

| Collection | Key | Value |
|---|---|---|
| `player_profile` | `{user_id}` | `display_name`, `level`, `currency` |
| `deck` | `{user_id}` | `equipped_card_ids: Array[String]` |
| `match_result` | `{match_id}` | `winner_team`, `player_stats`, `timestamp` |
| `shop_catalog` | `global` | 판매 중인 카드 목록 |

---

## Python 오케스트레이터 — 서비스 설계

> gserver는 모든 단계에서 심판 프로세스 관리를 담당한다.

### 기술 스택

| 라이브러리 | 용도 |
|---|---|
| FastAPI + uvicorn | REST API 서버 |
| asyncio.subprocess | Godot 프로세스 스폰 / 종료 |
| httpx | Nakama server-to-server API 호출 (Stage 1+) |
| Redis (선택) | 분산 배포 시 match registry 공유 |

### API 엔드포인트

```
POST /queue                      (Stage 0: 매칭 큐)
GET  /queue/{player_id}/status   (Stage 0: 매칭 상태 조회)

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
- referee가 예상치 않게 종료되면 → 매치 중단 처리
- 매치 최대 시간(20분) 초과 시 강제 종료 후 draw 처리

### 환경 변수

```
GODOT_BIN           = /usr/local/bin/godot
GAME_PATH           = /app/arena
PUBLIC_HOST         = game.arena.example.com
PORT_RANGE_START    = 7800
PORT_RANGE_END      = 7900
ALLOCATE_TIMEOUT_S  = 10
MATCH_MAX_DURATION_S = 1200

# Stage 1+ (없으면 Nakama 연동 스킵)
NAKAMA_URL          = http://nakama:7350
NAKAMA_HTTP_KEY     = defaultkey
```

---

## Godot 변경 사항 (Stage 1+)

### Client (Player Mode)

| 파일 | 변경 내용 |
|---|---|
| `src/global/nakama_service.gd` | Nakama SDK 초기화, session_token 관리 (신규) |
| `src/screen/login_screen.gd` | 자동 로그인 진입 화면 (신규) |
| `src/global/screen_manager.gd` | `LOGIN` 화면 추가, 로비 복귀 시 `save_deck_async()` 호출 |
| `src/global/player_data.gd` | `get_equipped_dict()`, `load_deck()` 메서드 추가 |
| `src/screen/lobby_screen.gd` | 랭킹 버튼 추가 |

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

## 배포 구조 (Stage 2)

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

## 미결 사항

| 항목 | 현재 결정 | 재검토 시점 |
|---|---|---|
| Stage 2 매칭 방식 | TBD (Go 모듈 vs gserver 확장) | Stage 1 완성 후 |
| referee 재접속 지원 | `get_active_match` RPC로 referee 주소 재조회 | Stage 2 |
| referee 클라이언트 인증 | player_id만 사용 (session_token 미전달) | Stage 2 |
| 포트 고갈 시 처리 | 503 반환 → 매칭 큐 재진입 유도 | Stage 1 |
| k8s 스케일아웃 | 단일 서버로 시작 | 플레이테스트 후 |
| referee 비정상 종료 | orchestrator 감지 → draw 처리 + 알림 | Stage 1 |
