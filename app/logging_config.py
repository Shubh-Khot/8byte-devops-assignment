"""JSON logging.

Loki and CloudWatch Logs Insights both parse JSON natively. Emitting plain
text here would mean writing regex extractors on the other end for every
field, so the formatting cost is paid once, at the source.
"""

import json
import logging
import sys
from datetime import UTC, datetime

# Attributes LogRecord always carries. Anything outside this set was attached
# by the caller via `extra=` and belongs in the JSON output.
_STANDARD_ATTRS = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__.keys()) | {
    "asctime",
    "message",
    "taskName",
}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }

        for key, value in record.__dict__.items():
            if key not in _STANDARD_ATTRS:
                payload[key] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())

    # uvicorn installs its own colourised handlers; drop them so we get one
    # consistent JSON stream instead of two competing formats.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True

    # The access log is replaced by our own middleware, which knows the
    # request id and the route template rather than the raw path.
    logging.getLogger("uvicorn.access").disabled = True
