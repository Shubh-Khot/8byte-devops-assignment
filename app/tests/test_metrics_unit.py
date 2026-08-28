"""Unit tests. No database, no network - these run on every PR in seconds."""

import pytest
from starlette.requests import Request

from metrics import route_template


def _request(scope_extra=None):
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/tasks/1",
        "headers": [],
    }
    scope.update(scope_extra or {})
    return Request(scope)


class FakeRoute:
    def __init__(self, path):
        self.path = path


def test_route_template_uses_the_matched_pattern_not_the_raw_path():
    req = _request({"route": FakeRoute("/tasks/{task_id}")})
    assert route_template(req) == "/tasks/{task_id}"


def test_route_template_collapses_unmatched_paths():
    assert route_template(_request()) == "unmatched"


@pytest.mark.parametrize("password", ["hunter2", "p@ss:word/with?chars"])
def test_safe_database_url_never_leaks_the_password(password, monkeypatch):
    from config import Settings

    s = Settings(
        env="test",
        db_host="db.internal",
        db_port=5432,
        db_name="tasksdb",
        db_user="tasks",
        db_password=password,
        db_pool_size=5,
        log_level="INFO",
    )
    assert password not in s.safe_database_url
    assert password in s.database_url
