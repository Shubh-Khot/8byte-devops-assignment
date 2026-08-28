"""Prometheus metrics. Labels use the route template, never the raw path."""

import time

from prometheus_client import Counter, Gauge, Histogram
from starlette.requests import Request
from starlette.responses import Response

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests.",
    ["method", "path", "status"],
)

LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency.",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

IN_FLIGHT = Gauge(
    "http_requests_in_flight",
    "Requests currently being served.",
)

DB_UP = Gauge(
    "app_database_up",
    "1 if the last readiness check reached the database, 0 otherwise.",
)


def route_template(request: Request) -> str:
    """Matched route pattern, or "unmatched" so stray URLs share one series."""
    route = request.scope.get("route")
    return getattr(route, "path", None) or "unmatched"


async def metrics_middleware(request: Request, call_next) -> Response:
    if request.url.path == "/metrics":
        return await call_next(request)

    start = time.perf_counter()
    IN_FLIGHT.inc()
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        status = 500
        raise
    finally:
        IN_FLIGHT.dec()
        elapsed = time.perf_counter() - start
        path = route_template(request)
        REQUESTS.labels(request.method, path, str(status)).inc()
        LATENCY.labels(request.method, path).observe(elapsed)

    return response
