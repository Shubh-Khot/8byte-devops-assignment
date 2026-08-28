# Two stages: wheels are built with a compiler present, the runtime image
# never gets one. Keeps the shipped image smaller and drops a whole class of
# "build tooling in production" CVE findings from the Trivy report.
FROM python:3.12-slim AS build

ENV PIP_NO_CACHE_DIR=1
WORKDIR /wheels

COPY app/requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt


FROM python:3.12-slim AS runtime

# Unbuffered stdout matters: without it logs sit in a pipe buffer and
# `docker logs` / CloudWatch show nothing while you are debugging a live issue.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=build /wheels /wheels
COPY app/requirements.txt .
RUN pip install --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY app/ .

# Baked in at build time by CI so a running container can report its commit.
ARG BUILD_SHA=dev
ENV BUILD_SHA=$BUILD_SHA

USER 10001
EXPOSE 8000

# Docker-level healthcheck for local/compose use. In ECS the real check is the
# ALB target group hitting /readyz; this one just makes `docker ps` honest.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"

# One worker per container, on purpose. Two workers behind one port means
# Prometheus scrapes whichever worker happens to answer, so counters appear
# to jump around. On Fargate the unit of scale is the task, so scale out with
# desired_count instead and keep the metrics honest.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
