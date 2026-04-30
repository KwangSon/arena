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


# ---------------------------------------------------------------------------
# Queue state  (2-player matchmaking for local testing without Nakama)
# ---------------------------------------------------------------------------

_queue_waiting: list[str] = []
_queue_matches: dict[str, dict] = {}
_queue_lock: asyncio.Lock | None = None


def _get_lock() -> asyncio.Lock:
    global _queue_lock
    if _queue_lock is None:
        _queue_lock = asyncio.Lock()
    return _queue_lock


async def _allocate_for_players(player_a: str, player_b: str) -> None:
    """Background task: spawn referee when 2 players are queued."""
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
        )

        registry[match_id] = MatchRecord(
            match_id=match_id,
            port=port,
            player_ids=[player_a, player_b],
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
        _queue_matches[player_a] = match_info
        _queue_matches[player_b] = match_info
        print(f"[queue] Match {match_id} ready on :{port} for {player_a}, {player_b}")

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
    lock = _get_lock()
    player_a = player_b = None

    async with lock:
        if req.player_id in _queue_waiting or req.player_id in _queue_matches:
            return {"status": "already_queued", "player_id": req.player_id}
        _queue_waiting.append(req.player_id)
        if len(_queue_waiting) >= 2:
            player_a = _queue_waiting.pop(0)
            player_b = _queue_waiting.pop(0)

    if player_a is not None:
        asyncio.create_task(_allocate_for_players(player_a, player_b))

    print(f"[queue] {req.player_id} joined — waiting: {_queue_waiting}")
    return {"status": "queued", "player_id": req.player_id}


@app.get("/queue/{player_id}/status")
async def queue_status(player_id: str) -> dict:
    if player_id in _queue_matches:
        return _queue_matches.pop(player_id)
    if player_id in _queue_waiting:
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
