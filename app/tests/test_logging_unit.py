import json
import logging

from logging_config import JsonFormatter


def _record(**extra):
    record = logging.LogRecord(
        name="app",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="request",
        args=(),
        exc_info=None,
    )
    record.__dict__.update(extra)
    return record


def test_formatter_emits_parseable_json():
    out = json.loads(JsonFormatter().format(_record()))
    assert out["msg"] == "request"
    assert out["level"] == "INFO"
    assert "ts" in out


def test_extra_fields_are_promoted_to_top_level_keys():
    out = json.loads(JsonFormatter().format(_record(request_id="abc123", status=200)))
    assert out["request_id"] == "abc123"
    assert out["status"] == 200
