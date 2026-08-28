# Challenges and resolutions

Everything below actually happened while building this. Where a problem produced an
error message, I have kept the real one.

---

## 1. Two uvicorn workers raced to create the schema

**Symptom.** First clean `docker compose up`, and the application logged this before
recovering on a retry:

```
"level": "WARNING", "msg": "database not ready", "attempt": 1,
"error": "(psycopg.errors.UniqueViolation) duplicate key value violates unique
constraint \"pg_class_relname_nsp_index\"
DETAIL: Key (relname, relnamespace)=(tasks_id_seq, 2200) already exists."
```

**Diagnosis.** The container ran uvicorn with `--workers 2`. Both workers execute the
lifespan startup hook, both call `Base.metadata.create_all()`, both check "do the tables
exist?" at the same moment, both get "no", and both issue `CREATE TABLE`. One wins; the
loser hits a unique violation on `pg_class`.

My retry loop masked it — the second attempt found the tables already there and carried
on — which is exactly why it was worth fixing properly. It only looked harmless because
of a workaround I had written for a different reason. With N Fargate tasks starting
simultaneously during a rolling deploy, the same race is much wider.

**Resolution.** A transaction-scoped Postgres advisory lock around the DDL:

```python
with engine.begin() as conn:
    conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _SCHEMA_LOCK_KEY})
    Base.metadata.create_all(conn)
```

Transaction-scoped (`pg_advisory_xact_lock`, not `pg_advisory_lock`) matters: the lock is
released on commit, and released automatically if the process dies mid-migration rather
than wedging every future boot. After the fix, the retry counter on a cold start is zero.

**What I would do in production.** Not this. Application containers should not run DDL at
all — migrations belong in Alembic, run as a one-shot ECS task before the rolling update.
The advisory lock is the right fix for the shape of this demo, and it is documented as
such in `db.py`.

---

## 2. A false "database unreachable" critical alert against a healthy database

**Symptom.** After wiring up Prometheus, this was firing:

```
DatabaseUnreachable   firing   Application cannot reach Postgres
```

The database was fine. `curl /readyz` returned `{"status":"ready","database":"ok"}`.

**Diagnosis.** `app_database_up` is a gauge, and I had only written to it inside the
`/readyz` handler. A Prometheus gauge defaults to 0. So the sequence was:

1. Container starts, gauge = 0 (default).
2. Nothing calls `/readyz` — the load generator only hits `/tasks`.
3. Prometheus scrapes `/metrics`, reads 0, and correctly reports what it was told.

The metric was not measuring the database. It was measuring *whether anyone had recently
asked about the database*.

This would have been invisible in AWS, which is the part that bothered me most: the ALB
health check polls `/readyz` every 15 seconds, so the gauge would always look fresh. The
bug would have sat there until the first time something else consumed that metric.

**Resolution.** Moved the check behind one function that both callers share, and added a
background task that refreshes it on a timer regardless of traffic:

```python
async def readiness_loop() -> None:
    while True:
        await asyncio.to_thread(check_database)   # psycopg is sync; don't stall the loop
        await asyncio.sleep(READINESS_INTERVAL_SECONDS)
```

Also seeded a real value during startup, before the first scrape can happen. Verified by
querying the gauge with zero traffic to the service: `app_database_up 1.0`.

**Lesson, and what I added because of it.** A gauge that is only written on a request path
is not a health metric. Four regression tests in `app/tests/test_readiness_unit.py` now
pin the behaviour, including that the gauge recovers *without* an HTTP request.

---

## 3. An SCP on the AWS account blocked `terraform plan`

**Symptom.** The first real plan against AWS got most of the way and then:

```
Error: fetching Availability Zones: operation error EC2: DescribeAvailabilityZones,
https response error StatusCode: 403, api error UnauthorizedOperation: You are not
authorized to perform: ec2:DescribeAvailabilityZones with an explicit deny in a
service control policy
```

**Diagnosis.** Not an IAM policy problem — an **explicit deny in an Organizations service
control policy**, which no amount of granting permissions to the user can override. The
`data "aws_availability_zones"` lookup is best practice (AZ names are per-account aliases,
so `ap-south-1a` is not the same physical zone in two different accounts), but it is a
hard dependency on a permission the stack does not otherwise need.

**Resolution.** Made the lookup optional rather than removing it:

```hcl
data "aws_availability_zones" "available" {
  count = length(var.availability_zones) > 0 ? 0 : 1
  state = "available"
}

azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available[0].names, 0, 2)
```

Discovery stays the default because it is the better behaviour; an explicit list is the
escape hatch. With `-var 'availability_zones=["ap-south-1a","ap-south-1b"]'` the plan
completed: **70 resources to add, 0 to change, 0 to destroy.**

**Lesson.** A data source is a permission dependency, and in an Organizations account the
blast radius of one denied read call is the entire plan.

---

## 4. Compose resolved every config path against the wrong directory

**Symptom.** With the monitoring compose file at `monitoring/docker-compose.monitoring.yml`,
Prometheus, Loki and Promtail all crash-looped:

```
error mounting "/host_mnt/Users/.../8byte-devops-assignment/prometheus/prometheus.yml"
to rootfs at "/etc/prometheus/prometheus.yml": ... not a directory:
Are you trying to mount a directory onto a file (or vice-versa)?
```

**Diagnosis.** Compose resolves relative bind-mount paths against the **project
directory** — the directory of the *first* `-f` file — not against the file the path is
written in. So `./prometheus/prometheus.yml`, written inside `monitoring/`, resolved to
`<repo-root>/prometheus/prometheus.yml`. That did not exist, so Docker created it as an
empty *directory* and mounted that over the config file.

The failure mode is nasty: it silently littered four empty directories into the repo root,
and the error message talks about mount types rather than the path being wrong.

**Resolution.** Moved the file to the repo root as `docker-compose.monitoring.yml` and
rewrote the paths to `./monitoring/...`, so they mean what they look like they mean. The
reasoning is a comment at the top of the file, because the next person will otherwise
"tidy" it back into `monitoring/`.

---

## 5. Alertmanager does not expand environment variables

**Symptom.**

```
level=ERROR msg="Loading configuration file failed" err="unsupported scheme \"\" for URL"
```

**Diagnosis.** I had written `api_url: "${SLACK_WEBHOOK_URL}"`. Unlike many tools,
Alertmanager does no environment substitution in its config — it read the literal string
`${SLACK_WEBHOOK_URL}` and correctly rejected it as a URL with no scheme.

**Resolution.** Switched to `api_url_file: /etc/alertmanager/slack_url` and mounted the
file. This turned out to be the better pattern anyway, and for the same reason the ECS
task definition uses `secrets` rather than `environment` for the database password: the
secret is mounted at runtime instead of being baked into a config file that lives in git.
The committed file holds an obvious placeholder.

---

## 6. `node-exporter` could not mount the host root on macOS

**Symptom.**

```
Error response from daemon: path / is mounted on / but it is not a shared or slave mount
```

**Diagnosis.** The documented mount is `/:/host:ro,rslave`. On Docker Desktop for macOS
containers run inside a Linux VM whose root is not a shared mount, so the daemon refuses
the bind outright.

**Resolution.** Dropped `rslave`. Plain `:ro` works on both platforms. On macOS the
resulting metrics describe the VM rather than the Mac, which is an acceptable limitation
for a local demo — and in AWS these metrics come from Container Insights, not from
node-exporter at all. Noted in a comment so nobody "fixes" it back to the Linux form.

---

## 7. Prometheus counters jumped around with multiple workers

**Symptom.** Request counters occasionally went *down* between scrapes.

**Diagnosis.** `prometheus_client` keeps counters in process memory. With
`uvicorn --workers 2` behind one port, each scrape is answered by whichever worker the
kernel happens to hand the connection to — so Prometheus was alternating between two
independent sets of counters.

**Resolution.** One worker per container, and scale out with `desired_count` instead. On
Fargate the unit of scale is the task, so nothing is lost: two tasks with one worker each
cost the same as one task with two workers, and every task is scraped as its own target
with its own consistent counters. The alternative — `prometheus_client`'s multiprocess
mode with a shared directory — adds real complexity for no benefit on this platform.

---

## 8. Terraform kept trying to undo the pipeline's deploys

**Symptom.** After the CD workflow deployed a new image, the next `terraform plan` wanted
to revert the ECS service to the image tag from the last apply.

**Diagnosis.** Both systems believe they own `task_definition`. CI registers a new task
definition revision and calls `update-service`; Terraform's state still holds the old
revision and dutifully plans to put it back. Whichever ran last would win, which means the
answer to "what is deployed?" depended on run ordering.

**Resolution.** An explicit ownership boundary:

```hcl
lifecycle {
  ignore_changes = [task_definition, desired_count]
}
```

Terraform owns the *shape* of the service — networking, roles, scaling policy, circuit
breaker. The pipeline owns *which image is running*. `desired_count` is in the list for
the same reason: autoscaling owns it after creation, and without this every plan would
try to reset a scaled-out service back to its initial count.

The same class of problem, with the same fix, hit `final_snapshot_identifier` — its value
embeds `formatdate(..., timestamp())`, so it showed a diff on *every* plan until it was
added to `ignore_changes`.

---

## 9. Docker served a stale layer and I debugged the wrong code

**Symptom.** After the readiness fix in #2, `docker compose up -d --build api` reported a
successful build, but the gauge still read 0. I spent a while re-reading correct code.

**Diagnosis.** `grep -c readiness_loop main.py` *inside the running container* returned 0.
The image did not contain the change at all — buildx had served a cached layer for the
`COPY app/ .` step. `--no-cache` produced the correct image immediately.

**Resolution.** Nothing to change in the repo, but it changed how I verify things. The
habit I took from it: when behaviour contradicts the source, first prove which bytes are
actually running. That is also why `BUILD_SHA` is baked into the image and returned by
`/healthz`, and why the smoke test asserts on it — a deploy that silently rolls back
otherwise "passes", because the old version answers health checks perfectly well.

---

## 10. Choosing where to give up isolation for cost

**Not a bug — the decision I went back and forth on most.**

A NAT gateway is ~$32/month per AZ before data charges, and it is the single largest line
item in this stack. Without one, Fargate tasks in private subnets cannot reach ECR to pull
their own image, so the service cannot start at all.

The options, none of them free:

| | cost | tradeoff |
|---|---|---|
| NAT per AZ | ~$96/mo (3 AZ) | correct, and absurd at this scale |
| One shared NAT | ~$32/mo | a single-AZ dependency for all egress |
| Interface VPC endpoints | ~$29/mo (4 × $7.20) | comparable cost, more moving parts |
| Tasks in public subnets | $0 | weaker isolation |

**Resolution.** One shared NAT gateway in both environments, with tasks and the database
in private subnets. That accepts a single-AZ dependency for outbound traffic in exchange
for keeping every workload off the public internet, in staging as well as production.

Putting staging's tasks in public subnets would save the $32 outright, and it is tempting
for an environment nobody depends on. I did not do it, because then staging stops being a
rehearsal for production and the difference is exactly the part that carries the security
risk.

---

## 11. Smaller things worth recording

**FastAPI's `Depends()` versus the linter.** `ruff` flags `session: Session = Depends(...)`
as B008 (function call in an argument default) — correct in general, and FastAPI's
documented idiom. Rather than suppress the rule, I switched to the `Annotated` form:
`SessionDep = Annotated[Session, Depends(get_session)]`. Same behaviour, declared once,
and the linter is right again instead of being told to be quiet.

**Ruff sorted the app's own imports as third-party.** The container runs with `/app` as
the working directory, so imports are flat (`import db`). Ruff could not tell those from
PyPI packages and interleaved them with `fastapi` and `sqlalchemy`. Fixed with
`known-first-party` in `.ruff.toml` rather than by restructuring the app into a package
purely to satisfy a tool.

**Dual-axis panels.** My first pass at the CloudWatch dashboards had "RDS throughput and
latency" as one widget with IOPS on the left axis and seconds on the right. Two unrelated
scales in one chart let you slide them until the lines appear to correlate. Split into
separate panels.

**RDS rejects some master usernames and some password characters.** `admin`, `postgres`
and `rdsadmin` are reserved, and a handful of special characters are refused in the master
password — both produce an `InvalidParameterValue` at create time that is annoying to
trace back to its cause. Encoded as a `validation` block on the variable and an
`override_special` on `random_password`, so it fails at plan time with a clear message
instead of failing at apply.

**`backup_retention_days = 0` silently disables PITR.** Not just "no scheduled snapshots" —
point-in-time recovery goes away too. There is now a validation rule rejecting 0, because
it is an easy mistake and an expensive one to discover.
