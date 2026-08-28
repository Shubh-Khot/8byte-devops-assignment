"""Task API: a small CRUD service with health endpoints, metrics and JSON logs."""

import asyncio
import logging
import os
import socket
import time
import uuid
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy.orm import Session

import db
from config import settings
from logging_config import configure_logging
from metrics import DB_UP, metrics_middleware, route_template
from models import Task
from schemas import TaskCreate, TaskOut, TaskUpdate

configure_logging(settings.log_level)
log = logging.getLogger("app")

BUILD_SHA = os.getenv("BUILD_SHA", "dev")
INSTANCE = socket.gethostname()

READINESS_INTERVAL_SECONDS = 15


def check_database() -> bool:
    """Probe the database and record the result on the gauge."""
    try:
        db.ping()
    except Exception as exc:
        DB_UP.set(0)
        log.error("database check failed", extra={"error": str(exc)})
        return False
    DB_UP.set(1)
    return True


async def readiness_loop() -> None:
    """Refresh the database gauge on a timer, independent of traffic.

    Without this the gauge only moves when something calls /readyz, so an idle
    service reports app_database_up = 0 and the alert fires against a healthy
    database.
    """
    while True:
        try:
            await asyncio.to_thread(check_database)
        except Exception:
            log.exception("readiness loop iteration failed")
        await asyncio.sleep(READINESS_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(_: FastAPI):
    log.info("starting", extra={"env": settings.env, "build": BUILD_SHA})
    for attempt in range(1, 11):
        try:
            db.init_schema()
            break
        except Exception as exc:
            log.warning("database not ready", extra={"attempt": attempt, "error": str(exc)})
            time.sleep(3)
    else:
        raise RuntimeError("database unreachable after 10 attempts")

    check_database()
    probe = asyncio.create_task(readiness_loop())

    yield

    probe.cancel()
    log.info("shutting down")


app = FastAPI(title="task-api", version=BUILD_SHA, lifespan=lifespan)
app.middleware("http")(metrics_middleware)


def get_session():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


SessionDep = Annotated[Session, Depends(get_session)]


@app.middleware("http")
async def access_log(request: Request, call_next):
    """One structured log line per request, with a correlation id."""
    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
    request.state.request_id = request_id

    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        log.exception(
            "request failed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "duration_ms": round((time.perf_counter() - start) * 1000, 2),
            },
        )
        raise

    duration_ms = round((time.perf_counter() - start) * 1000, 2)
    response.headers["X-Request-Id"] = request_id

    level = logging.DEBUG if request.url.path in ("/healthz", "/readyz") else logging.INFO
    log.log(
        level,
        "request",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "route": route_template(request),
            "status": response.status_code,
            "duration_ms": duration_ms,
            "instance": INSTANCE,
            "build": BUILD_SHA,
        },
    )
    return response


@app.get("/healthz")
def healthz():
    """Liveness. Never touches the database, or an outage would restart every task."""
    return {"status": "alive", "build": BUILD_SHA, "instance": INSTANCE}


@app.get("/readyz")
def readyz(response: Response):
    """Readiness. A 503 takes this task out of the target group without killing it."""
    if not check_database():
        response.status_code = 503
        return {"status": "degraded", "database": "unreachable"}

    return {"status": "ready", "database": "ok", "build": BUILD_SHA}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/tasks", response_model=list[TaskOut])
def list_tasks(session: SessionDep):
    return session.query(Task).order_by(Task.id.desc()).limit(100).all()


@app.post("/tasks", response_model=TaskOut, status_code=201)
def create_task(payload: TaskCreate, session: SessionDep):
    task = Task(title=payload.title)
    session.add(task)
    session.commit()
    log.info("task created", extra={"task_id": task.id})
    return task


@app.get("/tasks/{task_id}", response_model=TaskOut)
def get_task(task_id: int, session: SessionDep):
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    return task


@app.patch("/tasks/{task_id}", response_model=TaskOut)
def update_task(task_id: int, payload: TaskUpdate, session: SessionDep):
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    task.done = payload.done
    session.commit()
    return task


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int, session: SessionDep):
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    session.delete(task)
    session.commit()
    return Response(status_code=204)


@app.get("/boom")
def boom():
    """Deliberate 500, used to demonstrate the error-rate alert."""
    raise RuntimeError("synthetic failure for alerting demo")


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={
            "detail": "internal error",
            "request_id": getattr(request.state, "request_id", None),
        },
    )
