"""Regression tests for the database readiness gauge.

Written after a false alert: app_database_up starts at 0, and originally it
was only ever written by a request to /readyz. With nothing polling that
endpoint the gauge sat at its default and Prometheus reported the database as
unreachable while it was perfectly healthy. These tests pin down that the
gauge tracks the last real check, not the last request.
"""

import pytest

import db
from metrics import DB_UP


@pytest.fixture
def check(monkeypatch):
    from main import check_database

    return check_database


def _gauge() -> float:
    return DB_UP._value.get()


def test_successful_check_sets_the_gauge_up(check, monkeypatch):
    monkeypatch.setattr(db, "ping", lambda: None)
    assert check() is True
    assert _gauge() == 1


def test_failed_check_sets_the_gauge_down(check, monkeypatch):
    def boom():
        raise OSError("connection refused")

    monkeypatch.setattr(db, "ping", boom)
    assert check() is False
    assert _gauge() == 0


def test_check_does_not_propagate_database_errors(check, monkeypatch):
    # The caller is a background task and an HTTP handler; neither should have
    # to catch anything. A raise here would kill the readiness loop outright.
    def boom():
        raise RuntimeError("some driver-level explosion")

    monkeypatch.setattr(db, "ping", boom)
    assert check() is False


def test_gauge_recovers_without_a_request(check, monkeypatch):
    def boom():
        raise OSError("down")

    monkeypatch.setattr(db, "ping", boom)
    check()
    assert _gauge() == 0

    # The database comes back. The background loop calls check_database again;
    # no HTTP request is involved, and the gauge must follow.
    monkeypatch.setattr(db, "ping", lambda: None)
    check()
    assert _gauge() == 1
