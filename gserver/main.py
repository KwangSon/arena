import asyncio
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="gserver")

GAME_PATH = os.getenv("GAME_PATH", ".")
GODOT_BIN = os.getenv("GODOT_BIN", os.path.join(GAME_PATH, "godot"))
PUBLIC_HOST = os.getenv("PUBLIC_HOST", "localhost")
PORT_RANGE_START = int(os.getenv("PORT_RANGE_START", "7800"))
PORT_RANGE_END = int(os.getenv("PORT_RANGE_END", "7900"))
ALLOCATE_TIMEOUT_S = int(os.getenv("ALLOCATE_TIMEOUT_S", "10"))


# ---------------------------------------------------------------------------
# Port pool
# ---------------------------------------------------------------------------

class PortPool:
    def __init__(self, start: int, end: int) -> None:
        self._free: set[int] = set(range(start, end))
        self._lock = asyncio.Lock()

    async def acquire(self) -> int:
        async with self._lock:
            if not self._free:
                raise HTTPException(503, "No available referee ports")
            return self._free.pop()

    async def release(self, port: int) -> None:
        async with self._lock:
            self._free.add(port)


port_pool = PortPool(PORT_RANGE_START, PORT_RANGE_END)


# ---------------------------------------------------------------------------
# Match registry
# ---------------------------------------------------------------------------

@dataclass
class MatchRecord:
    match_id: str
    port: int
    player_ids: list[str]
    proc: asyncio.subprocess.Process | None = None
    started_at: datetime = field(default_factory=datetime.utcnow)
    ready: bool = False

registry: dict[str, MatchRecord] = {}
ready_events: dict[str, asyncio.Event] = {}


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class AllocateRequest(BaseModel):
    match_id: str = ""
    player_ids: list[str]
    game_mode: str = "tdm"


class AllocateResponse(BaseModel):
    match_id: str
    referee_host: str
    referee_port: int


class ReadyRequest(BaseModel):
    port: int


class ResultRequest(BaseModel):
    winner_team: int
    player_stats: list[dict]


class QueueRequest(BaseModel):
    player_id: str
    game_mode: str = "1v1"


@dataclass
class QueueBucket:
    waiting: list[str] = field(default_factory=list)
    matches: dict[str, dict] = field(default_factory=dict)
    team_size: int = 1
    required: int = 2


_queues: dict[str, QueueBucket] = {
    "1v1": QueueBucket(team_size=1, required=2),
    "3v3": QueueBucket(team_size=3, required=6),
}
_queue_lock: asyncio.Lock | None = None


def _get_lock() -> asyncio.Lock:
    global _queue_lock
    if _queue_lock is None:
        _queue_lock = asyncio.Lock()
    return _queue_lock


async def _allocate_for_players(
    player_ids: list[str], game_mode: str
) -> None:
    """Background task: spawn referee when enough players are queued."""
    bucket = _queues[game_mode]
    try:
        match_id = str(uuid.uuid4())
        port = await port_pool.acquire()
        event = asyncio.Event()
        ready_events[match_id] = event

        proc = await asyncio.create_subprocess_exec(
            GODOT_BIN, "--headless",
            "--path", GAME_PATH,
            "--",
            "--mode=referee",
            f"--match-id={match_id}",
            f"--port={port}",
            f"--orchestrator-url=http://{PUBLIC_HOST}:8080",
            f"--game-mode={game_mode}",
        )

        registry[match_id] = MatchRecord(
            match_id=match_id,
            port=port,
            player_ids=player_ids,
            proc=proc,
        )

        try:
            await asyncio.wait_for(event.wait(), timeout=ALLOCATE_TIMEOUT_S)
        except TimeoutError:
            proc.kill()
            registry.pop(match_id, None)
            ready_events.pop(match_id, None)
            await port_pool.release(port)
            print(f"[queue] Referee for match {match_id} timed out")
            return

        match_info = {
            "status": "matched",
            "match_id": match_id,
            "referee_host": PUBLIC_HOST,
            "referee_port": port,
        }
        for pid in player_ids:
            bucket.matches[pid] = match_info
        print(
            f"[queue] Match {match_id} ({game_mode}) ready on :{port}"
            f" for {player_ids}"
        )

    except Exception as e:
        print(f"[queue] Allocation error: {e}")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.post("/allocate", response_model=AllocateResponse)
async def allocate(req: AllocateRequest) -> AllocateResponse:
    match_id = req.match_id or str(uuid.uuid4())
    port = await port_pool.acquire()

    event = asyncio.Event()
    ready_events[match_id] = event

    proc = await asyncio.create_subprocess_exec(
        GODOT_BIN, "--headless",
        "--path", GAME_PATH,
        "--",
        "--mode=referee",
        f"--match-id={match_id}",
        f"--port={port}",
        f"--orchestrator-url=http://{PUBLIC_HOST}:8080",
        f"--game-mode={req.game_mode}",
    )

    registry[match_id] = MatchRecord(
        match_id=match_id,
        port=port,
        player_ids=req.player_ids,
        proc=proc,
    )

    try:
        await asyncio.wait_for(event.wait(), timeout=ALLOCATE_TIMEOUT_S)
    except TimeoutError:
        proc.kill()
        del registry[match_id]
        del ready_events[match_id]
        await port_pool.release(port)
        raise HTTPException(504, f"Referee for match {match_id} did not report ready in time")

    return AllocateResponse(
        match_id=match_id,
        referee_host=PUBLIC_HOST,
        referee_port=port,
    )


@app.post("/match/{match_id}/ready")
async def match_ready(match_id: str, req: ReadyRequest) -> dict:
    if match_id not in registry:
        raise HTTPException(404, f"Unknown match_id: {match_id}")
    registry[match_id].ready = True
    if match_id in ready_events:
        ready_events[match_id].set()
    return {"ok": True}


@app.post("/match/{match_id}/result")
async def match_result(match_id: str, req: ResultRequest) -> dict:
    if match_id not in registry:
        raise HTTPException(404, f"Unknown match_id: {match_id}")
    record = registry.pop(match_id)
    ready_events.pop(match_id, None)
    await port_pool.release(record.port)
    # TODO: forward to Nakama server-to-server API
    print(f"[result] match={match_id} winner_team={req.winner_team} stats={req.player_stats}")
    return {"ok": True}


@app.get("/match/{match_id}")
async def get_match(match_id: str) -> dict:
    if match_id not in registry:
        raise HTTPException(404, f"Unknown match_id: {match_id}")
    r = registry[match_id]
    return {
        "match_id": r.match_id,
        "referee_host": PUBLIC_HOST,
        "referee_port": r.port,
        "player_ids": r.player_ids,
        "ready": r.ready,
        "started_at": r.started_at.isoformat(),
    }


@app.post("/queue")
async def queue_join(req: QueueRequest) -> dict:
    if req.game_mode not in _queues:
        raise HTTPException(400, f"Unknown game_mode: {req.game_mode}")
    bucket = _queues[req.game_mode]
    lock = _get_lock()
    batch: list[str] | None = None

    async with lock:
        all_ids = (
            {pid for b in _queues.values() for pid in b.waiting}
            | {pid for b in _queues.values() for pid in b.matches}
        )
        if req.player_id in all_ids:
            return {
                "status": "already_queued",
                "player_id": req.player_id,
            }
        bucket.waiting.append(req.player_id)
        if len(bucket.waiting) >= bucket.required:
            batch = [
                bucket.waiting.pop(0) for _ in range(bucket.required)
            ]

    if batch is not None:
        asyncio.create_task(
            _allocate_for_players(batch, req.game_mode)
        )

    print(
        f"[queue] {req.player_id} joined {req.game_mode}"
        f" — waiting: {bucket.waiting}"
    )
    return {"status": "queued", "player_id": req.player_id}


@app.get("/queue/{player_id}/status")
async def queue_status(player_id: str) -> dict:
    for bucket in _queues.values():
        if player_id in bucket.matches:
            return bucket.matches.pop(player_id)
        if player_id in bucket.waiting:
            return {"status": "waiting"}
    raise HTTPException(404, f"Player {player_id} not in queue")


@app.get("/health")
async def health() -> dict:
    return {
        "active_matches": len(registry),
        "available_ports": len(port_pool._free),
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
