# Walkthrough

Notes for recording the demo, in the order that tells the clearest story. Roughly
10 minutes.

Before recording:

```bash
make monitoring          # everything up
make load                # 60s of traffic so the dashboards are not empty
```

---

### 1. What this is (~30s)

FastAPI service over Postgres. The application is deliberately boring; the work is
everything around it. Show the repo tree once.

### 2. It runs (~1 min)

```bash
curl -s localhost:8000/readyz | jq
curl -s -XPOST localhost:8000/tasks -H 'content-type: application/json' -d '{"title":"demo"}' | jq
curl -s localhost:8000/tasks | jq
```

Then show the two health endpoints and say why they differ — this is the decision worth
leading with. Liveness never touches the database; readiness does. If liveness checked
the database, a 20-second RDS blip would restart every task at once.

### 3. Terraform (~2.5 min)

Do not read the files aloud. Show three things:

- `terraform/envs/staging/main.tf` — thin root, five modules, and the comment block
  listing exactly how staging differs from prod. Then `diff` it against prod.
- `terraform/modules/security/main.tf` — security groups referencing each other by ID,
  and the fact that the database group has **no egress rules at all**.
- `terraform/modules/network/main.tf` — the data-tier route table with no default route.
  Say the line: the route table is what keeps RDS off the internet, the security group is
  the second layer.

```bash
make tf-validate     # all roots and modules validate
```

Mention the real plan: **70 resources, 0 errors**, and that the AZ data source had to be
made optional because an SCP on the account denies `ec2:DescribeAvailabilityZones`
(`CHALLENGES.md` §3).

### 4. The pipeline (~2 min)

Walk `.github/workflows/cd.yml` top to bottom, but only stop at the four decisions:

1. The merge commit is retested — CI tested the PR branch, not what actually ships.
2. Built once, scanned, and *that* image pushed. Production promotes the tag staging ran;
   it never rebuilds.
3. `environment: production` with required reviewers **is** the approval gate. Nothing in
   the file can bypass it.
4. The smoke test asserts on the reported build SHA, not just a 200 — otherwise a deploy
   that silently rolled back still passes.

Show `scripts/smoke-test.sh` running against local:

```bash
make smoke
```

Also worth 20 seconds: OIDC, so there are no AWS keys in GitHub at all.

### 5. Monitoring (~3 min)

This is the strongest part. Grafana at <http://localhost:3000>.

**Service Health** — top row of SLI tiles, then explain the layout is triage order:
traffic → errors → latency → capacity. Point out that error rate is a *percentage*, not a
count, and that p50 sits next to p99 on purpose.

**Infrastructure & Database** — host and container resources, then the Postgres section.
Cache hit ratio and connections-by-state are the two that matter.

Then make it fire:

```bash
./scripts/generate-load.sh 120 errors
```

Watch the error-rate panel climb past the 5% threshold line, then:

```bash
open http://localhost:9090/alerts     # HighErrorRate: pending -> firing
open http://localhost:9093            # reaches Alertmanager
```

Show the log panel filtering on `level` — and mention that Promtail parses the app's JSON
and promotes `level` and `route` to labels, but deliberately *not* `request_id`, because
that has millions of values and would blow up the index.

Then the AWS side: `terraform/modules/observability/dashboards.tf`, two dashboards and ten
alarms defined as code. Point at one `treat_missing_data` and say why it differs per
alarm — `notBreaching` on error rate (no requests means no errors), `breaching` on
unhealthy hosts (no data is worse than a bad answer).

### 6. Two bugs I found and fixed (~1.5 min)

Worth more than any feature, because they show the system caught real problems.

**The false critical alert.** `app_database_up` was only written inside the `/readyz`
handler, so with nothing polling it the gauge sat at its default of 0 and Prometheus
reported the database as down while it was perfectly healthy. The metric was measuring
whether anyone had recently *asked*, not the database. Fixed with a background refresh
loop; four regression tests now pin it. Note that AWS would have hidden this — the ALB
polls `/readyz` every 15 seconds.

**The schema race.** Two uvicorn workers both ran `create_all()` at boot and one died on a
`UniqueViolation`. Fixed with a transaction-scoped Postgres advisory lock — and the real
answer, stated in the code, is that application containers should not run DDL at all.

### 7. Close (~30s)

Point at `CHALLENGES.md` and the "what I would build next" list in the README: Alembic
migrations as a pre-deploy task, canary using the second target group that is already
provisioned, and OpenTelemetry on top of the request IDs that already flow end to end.
