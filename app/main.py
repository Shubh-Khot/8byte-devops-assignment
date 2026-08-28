"""Task API - a small CRUD service used as the payload for the platform work.

The application logic is deliberately boring. What matters here is that it
behaves like something you can actually operate: structured logs, Prometheus
metrics, and health endpoints that mean different things.
"""

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

# Set by the CI pipeline at build time so a running container can tell you
# exactly which commit it came from. Saves a lot of "which version is live?".
BUILD_SHA = os.getenv("BUILD_SHA", "dev")
INSTANCE = socket.gethostname()


# How often the background probe re-checks the database. Matches the ALB
# health check interval so the metric never goes stale between polls.
READINESS_INTERVAL_SECONDS = 15


def check_database() -> bool:
    """Probe the database and record the result on the gauge.

    Both /readyz and the background task go through here so there is exactly
    one place that decides what "the database is up" means.
    """
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

    Without this the gauge only moves when something calls /readyz, so a quiet
    service reports app_database_up = 0 - its startup default - and the
    DatabaseUnreachable alert fires against a perfectly healthy database.
    In AWS the ALB polls /readyz every 15s and hides the problem; anywhere
    without a health checker in front of it, the metric is simply wrong.
    """
    while True:
        try:
            # The probe is blocking (psycopg is synchronous), so it runs in a
            # worker thread rather than stalling the event loop for the
            # duration of the connect timeout.
            await asyncio.to_thread(check_database)
        except Exception:
            log.exception("readiness loop iteration failed")
        await asyncio.sleep(READINESS_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(_: FastAPI):
    log.info("starting", extra={"env": settings.env, "build": BUILD_SHA})
    # Retry briefly: on a fresh `docker compose up` the app usually wins the
    # race against Postgres, and crash-looping over a 3 second startup delay
    # is a waste of everyone's time.
    for attempt in range(1, 11):
        try:
            db.init_schema()
            break
        except Exception as exc:
            log.warning("database not ready", extra={"attempt": attempt, "error": str(exc)})
            time.sleep(3)
    else:
        raise RuntimeError("database unreachable after 10 attempts")

    check_database()  # publish a real value before the first scrape can happen
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


# Annotated alias rather than `session: Session = Depends(get_session)` in
# every signature. Same behaviour, but the dependency is declared once, and it
# keeps a mutable default out of the function signature.
SessionDep = Annotated[Session, Depends(get_session)]


@app.middleware("http")
async def access_log(request: Request, call_next):
    """One structured line per request, carrying a correlation id.

    The id is taken from X-Request-Id if a proxy already set one, so a trace
    survives across the ALB and any future services behind it.
    """
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

    # Health checks fire every few seconds from the ALB and from ECS. Logging
    # them at INFO buries everything else and costs real money in CloudWatch.
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
    """Liveness. Process-level only, never touches the database.

    If this checked the DB, a brief database outage would restart every task
    at once and turn a recoverable blip into a cold start for the whole fleet.
    """
    return {"status": "alive", "build": BUILD_SHA, "instance": INSTANCE}


@app.get("/readyz")
def readyz(response: Response):
    """Readiness. Returns 503 when the database is unreachable, which takes
    this task out of the ALB target group without killing it."""
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
    """Deliberate 500. Used to prove the error-rate panel and the alert fire.

    Kept out of the docs; it is a demo hook, not a feature.
    """
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
