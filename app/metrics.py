"""Prometheus instrumentation.

Hand-rolled rather than pulled from a library so the label cardinality is
something I control. The route *template* is used as a label, never the raw
path: `/tasks/{task_id}` is one series, `/tasks/1`, `/tasks/2`, ... would be
one series per task and would eventually take Prometheus down.
"""

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
    # Tuned for a small CRUD API: most responses land under 100ms, and the
    # default buckets waste resolution on the 2.5s-10s range we never see.
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
    """Return the matched route pattern, or a placeholder for unmatched paths.

    Unmatched requests (scanners hitting /wp-login.php and friends) all collapse
    into a single "unmatched" series instead of creating one per bogus URL.
    """
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
        # An unhandled exception is still a 500 as far as the caller is
        # concerned, so record it before letting the handler re-raise.
        status = 500
        raise
    finally:
        IN_FLIGHT.dec()
        elapsed = time.perf_counter() - start
        path = route_template(request)
        REQUESTS.labels(request.method, path, str(status)).inc()
        LATENCY.labels(request.method, path).observe(elapsed)

    return response
