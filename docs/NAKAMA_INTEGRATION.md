# Nakama Integration Plan

## 목적

Nakama를 **최소한**으로 사용하여 아래 3가지만 처리한다.

1. **인증** — Device ID 자동 로그인 (계정 UI 없음)
2. **영속 저장** — 골드 + 보유카드 + 덱
3. **랭킹** — 시즌 승리수

Nakama 매치메이킹·릴레이·채팅·소셜·Go 커스텀 모듈은 사용하지 않는다.

---

## Mock vs Real Mode

`project.godot`의 `nakama/ip`가 비어있으면 → **Mock Mode** (Nakama 서버 없이 전체 동작).

---

## 화면 흐름 변경

```
기존: main.gd → LOBBY
변경: main.gd → LOGIN → LOBBY
```

LoginScreen은 버튼 없이 `_ready()`에서 자동 진행. 사용자 입력 없음.

| 모드 | 동작 |
|------|------|
| Mock | Nakama 통신 없이 즉시 `login_complete` 발생 |
| Real | `authenticate_device_async(OS.get_unique_id())` → 완료되면 `login_complete` 발생 |

인증 성공/실패 여부만 확인. 유저명·계정 정보는 사용하지 않음.

---

## 역할 분담

| 기능 | 담당 |
|------|------|
| Device 인증 | NakamaService.login_async() |
| 프로필/덱 저장·불러오기 | NakamaService — Nakama Storage R/W |
| 카드 구매 | PlayerData.buy_card() (로컬, 골드 검증 클라이언트 신뢰) |
| 랭킹 조회 | NakamaService.get_leaderboard_async() |
| **매치 후 랭킹 기록** | **gserver** — Nakama HTTP API 서버-투-서버 |

---

## 신규 파일

| 파일 | 역할 |
|------|------|
| `src/global/nakama_service.gd` | Autoload — 인증·저장·랭킹 단일 창구 |
| `src/screen/login_screen.gd` | 자동 로그인 진입 화면 (스피너만 표시) |

## 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `src/global/screen_manager.gd` | `LOGIN` 화면 추가, 로비 복귀 시 `save_deck_async()` 호출 |
| `src/main.gd` | 시작 화면을 `LOGIN`으로 변경 |
| `src/global/player_data.gd` | `get_equipped_dict()`, `load_deck()` 메서드 추가 |
| `src/screen/lobby_screen.gd` | 랭킹 버튼 추가 |
| `gserver/main.py` | 매치 결과 후 Nakama 랭킹 기록 (`NAKAMA_URL` env 설정 시만) |
| `project.godot` | `NakamaService` autoload 등록 |

---

## NakamaService API

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

---

## Nakama Storage 스키마

| Collection | Key | Value |
|---|---|---|
| `player` | `profile` | `{"gold": 2000, "owned_card_ids": ["armor"]}` |
| `player` | `deck` | `{"equipped": {"2": "armor", "3": "shoes"}}` |

Leaderboard ID: `season_wins` (DESCENDING, BEST)

---

## gserver 랭킹 연동

```
환경변수: NAKAMA_URL, NAKAMA_HTTP_KEY
없으면 스킵 → Mock 환경 영향 없음
```
