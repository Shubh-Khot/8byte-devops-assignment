"""Integration tests: real FastAPI app against a real Postgres.

Marked `integration` so `pytest -m "not integration"` still works on a laptop
with no database running. CI starts a Postgres service container and runs the
whole file.
"""

import os

import pytest
from fastapi.testclient import TestClient

pytestmark = pytest.mark.integration


@pytest.fixture(scope="module")
def client():
    if not os.getenv("DB_HOST"):
        pytest.skip("DB_HOST not set - integration tests need a live Postgres")

    from main import app

    import db

    # Start from a clean table so assertions on counts are deterministic when
    # the same database is reused across runs.
    from models import Base

    Base.metadata.drop_all(db.engine)

    with TestClient(app) as c:
        yield c


def test_readyz_reports_the_database_as_reachable(client):
    r = client.get("/readyz")
    assert r.status_code == 200
    assert r.json()["database"] == "ok"


def test_healthz_does_not_require_the_database(client):
    assert client.get("/healthz").json()["status"] == "alive"


def test_task_lifecycle(client):
    created = client.post("/tasks", json={"title": "write terraform"})
    assert created.status_code == 201
    task_id = created.json()["id"]
    assert created.json()["done"] is False

    fetched = client.get(f"/tasks/{task_id}")
    assert fetched.status_code == 200
    assert fetched.json()["title"] == "write terraform"

    updated = client.patch(f"/tasks/{task_id}", json={"done": True})
    assert updated.json()["done"] is True

    assert client.delete(f"/tasks/{task_id}").status_code == 204
    assert client.get(f"/tasks/{task_id}").status_code == 404


def test_rejects_empty_title(client):
    assert client.post("/tasks", json={"title": ""}).status_code == 422


def test_missing_task_returns_404_not_500(client):
    r = client.get("/tasks/999999")
    assert r.status_code == 404
    assert r.json()["detail"] == "task not found"


def test_metrics_endpoint_exposes_request_counters(client):
    client.get("/tasks")
    body = client.get("/metrics").text

    assert "http_requests_total" in body
    assert 'path="/tasks"' in body
    # The route template, not the expanded path - guards the cardinality fix.
    client.get("/tasks/999999")
    body = client.get("/metrics").text
    assert 'path="/tasks/{task_id}"' in body
    assert 'path="/tasks/999999"' not in body


def test_request_id_is_echoed_back(client):
    r = client.get("/healthz", headers={"X-Request-Id": "trace-me-123"})
    assert r.headers["X-Request-Id"] == "trace-me-123"
