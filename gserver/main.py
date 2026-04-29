import asyncio
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="gserver")

GODOT_BIN = os.getenv("GODOT_BIN", "godot")
GAME_PATH = os.getenv("GAME_PATH", ".")
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
