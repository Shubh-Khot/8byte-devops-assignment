# Task API — infrastructure, delivery and observability

A small FastAPI service backed by PostgreSQL, with everything around it that makes it
operable: Terraform for the AWS infrastructure, GitHub Actions for delivery, and a
metrics/logging stack that runs identically on a laptop and in AWS.

The application is intentionally boring — a CRUD API over one table. Everything
interesting in this repository is the platform around it.

```
                            ┌──────────────────────────────────────────────┐
   git push main            │  AWS account, ap-south-1                     │
        │                   │                                              │
        ▼                   │   ┌────────── VPC 10.20.0.0/16 ───────────┐  │
  ┌───────────┐   OIDC      │   │                                       │  │
  │  GitHub   │────────────▶│   │  public    ┌─────┐                    │  │
  │  Actions  │  no static  │   │  subnets   │ ALB │◀── internet        │  │
  └───────────┘  keys       │   │            └──┬──┘                    │  │
        │                   │   │               │ :8000                 │  │
        │ push image        │   │  private   ┌──▼───────────┐           │  │
        ▼                   │   │  subnets   │ ECS Fargate  │           │  │
     ┌──────┐               │   │            │  task-api    │           │  │
     │ ECR  │──────────────▶│   │            └──┬───────────┘           │  │
     └──────┘  pull         │   │               │ :5432                 │  │
                            │   │  data      ┌──▼───────────┐           │  │
                            │   │  subnets   │ RDS Postgres │           │  │
                            │   │  (no route │  Multi-AZ    │           │  │
                            │   │   out)     └──────────────┘           │  │
                            │   └───────────────────────────────────────┘  │
                            │                                              │
                            │   CloudWatch: logs · metrics · 2 dashboards  │
                            │   Secrets Manager: DB credentials            │
                            └──────────────────────────────────────────────┘
```

---

## Contents

| Path | What is in it |
|---|---|
| `app/` | FastAPI service, tests, Prometheus instrumentation, JSON logging |
| `terraform/modules/` | `network`, `security`, `database`, `ecs`, `observability` |
| `terraform/envs/` | `staging` and `prod` roots — same modules, different dials |
| `terraform/bootstrap/` | State bucket and the GitHub OIDC role. Run once. |
| `.github/workflows/` | `ci.yml` (PRs), `cd.yml` (deploys), `infra.yml` (Terraform) |
| `monitoring/` | Prometheus, Loki, Promtail, Alertmanager, 2 Grafana dashboards |
| `scripts/` | Smoke test, load generator, teardown |
| `docs/` | Runbook, demo script |
| `CHALLENGES.md` | What went wrong while building this, and how it was resolved |

---

## Running it locally

The fastest path to something you can click on. No AWS account needed.

```bash
git clone <this repo> && cd 8byte-devops-assignment

make up        # API + Postgres
make smoke     # prove it works end to end
```

`make up` gives you:

| | |
|---|---|
| API docs | <http://localhost:8000/docs> |
| Health (liveness) | <http://localhost:8000/healthz> |
| Readiness | <http://localhost:8000/readyz> |
| Metrics | <http://localhost:8000/metrics> |

### With the full observability stack

```bash
make monitoring   # adds Prometheus, Loki, Promtail, Grafana, Alertmanager, exporters
make load         # 60s of traffic so the dashboards have something to draw
```

| | |
|---|---|
| Grafana | <http://localhost:3000> (admin/admin) |
| Prometheus | <http://localhost:9090> |
| Alertmanager | <http://localhost:9093> |

Two dashboards are provisioned automatically from `monitoring/grafana/dashboards/`.

### Tests

```bash
make test        # 17 tests: unit + integration against a real Postgres
make lint        # ruff check + format
make audit       # pip-audit on dependencies, Trivy on the image
```

Tests run inside a container rather than against the host interpreter, so they behave
identically here and in CI regardless of what Python is installed locally.

---

## Deploying to AWS

### 1. Bootstrap (once per account)

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Creates the versioned, encrypted S3 bucket that holds Terraform state, plus the GitHub
OIDC provider and the CI deploy role. Note the outputs:

```bash
terraform output state_bucket             # -> for -backend-config
terraform output github_actions_role_arn  # -> GitHub repo variable AWS_DEPLOY_ROLE_ARN
```

### 2. An environment

```bash
cd terraform/envs/staging
terraform init -backend-config="bucket=$(terraform -chdir=../../bootstrap output -raw state_bucket)"
terraform plan
terraform apply
```

Then:

```bash
terraform output app_url        # http://taskapi-staging-alb-....ap-south-1.elb.amazonaws.com
terraform output dashboards     # console links to both CloudWatch dashboards
```

The first apply takes 10–15 minutes; RDS is most of it.

> The very first apply deploys the placeholder `bootstrap` image tag, so the service will
> not have a real image until the pipeline runs once. That is intentional — infrastructure
> and application releases are separate concerns, and the pipeline owns the image.

### 3. Wire up the pipeline

In the GitHub repository settings:

**Variables**
| Name | Value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | the `github_actions_role_arn` output |
| `TF_STATE_BUCKET` | the `state_bucket` output |

**Secrets**
| Name | Value |
|---|---|
| `SLACK_WEBHOOK_URL` | optional; notifications are skipped without it |

**Environments** — create `staging` and `production`. On `production`, add required
reviewers. That setting *is* the manual approval gate; nothing in the workflow file can
bypass it.

### 4. Tearing it down

```bash
./scripts/teardown.sh staging
```

Plain `terraform destroy` fails on this stack — RDS deletion protection and a non-empty
ECR repository both block it. The script clears those first.

---

## Architecture decisions

### ECS Fargate rather than EKS or EC2

EKS costs $73/month for the control plane before a single pod runs, and brings a second
system (Kubernetes RBAC, its own networking, cluster upgrades) to operate. Nothing about
this workload needs it. EC2 with an Auto Scaling Group means owning AMI builds, patching,
and instance draining.

Fargate has neither problem: no nodes to patch, per-second billing, and the deployment
primitives (circuit breaker, rolling updates, capacity providers) are built in. The
honest tradeoff is that Fargate is more expensive per vCPU-hour than a well-packed EC2
fleet — that crossover happens at a scale far beyond this.

### Three subnet tiers, not two

Public (load balancer), private (application), data (database). The data tier's route
table has **no default route at all** — that is what actually keeps the database off the
internet. The security group is the second layer, not the first. Two controls that fail
independently beats one control you trust completely.

### `/healthz` and `/readyz` mean different things

This is the decision I would defend hardest.

- `/healthz` — liveness. Process-level only, **never touches the database**. Failing it
  restarts the container, so it must only fail for things a restart can fix.
- `/readyz` — readiness. Checks the database. Failing it removes the task from the ALB
  target group *without* restarting it.

If liveness checked the database, a 20-second RDS blip would restart every task
simultaneously and turn a recoverable hiccup into a cold start for the whole fleet.

The cost of this design is real and worth stating: because readiness accurately reflects
a shared dependency, all tasks fail it *at the same time* when the database blips, and
the target group can drain to zero. The failure is correlated precisely because the check
is honest. `unhealthy_threshold: 3` × `interval: 15s` buys ~45 seconds of tolerance
before eviction. At two tasks that is the right trade; at two hundred it would not be,
and the answer there is serving degraded cached responses rather than 503s.

### Terraform state, and why there is no DynamoDB table

State lives in S3, one key per environment, versioned and encrypted. Versioning is the
actual disaster-recovery story: a truncated state file is recoverable by restoring the
previous object version, and unrecoverable without it.

Locking uses `use_lockfile = true` (S3 conditional writes, Terraform ≥ 1.10) rather than
the traditional DynamoDB table. Same mutual exclusion, one less resource to provision,
pay for and grant IAM on. `dynamodb_table` is now deprecated in the backend config —
worth knowing which one you are looking at when you inherit an older repo.

The bucket name is **not** committed; it embeds the AWS account id and is passed with
`-backend-config` at init time, so the repo runs in any account.

### Environments differ by variables, not by copies of the code

`staging` and `prod` call the same five modules. "How does production differ?" is
answerable by diffing two files:

| | staging | prod | why |
|---|---|---|---|
| NAT gateway | none — tasks in public subnets | one, tasks private | ~$32/mo vs. isolation |
| RDS | single-AZ `db.t3.micro` | Multi-AZ `db.t4g.small` | failover costs ~2× |
| Tasks | 1–3, all Spot | 2–10, all on-demand | Spot reclaims are fine in staging |
| Backups | 7 days | 30 days, deletion protection | recovery window |
| Logs | 7 days, `DEBUG` | 30 days, `INFO` | CloudWatch ingestion is the cost |
| KMS | AWS-managed | customer-managed key | rotation and revocation |
| Flow logs | off | on, 30 days | forensics |

### Terraform is not applied by CI on merge

`cd.yml` deploys application images automatically after approval. `infra.yml` **plans**
on every PR and comments the diff, but only applies on an explicit manual dispatch.

Application deploys are reversible in two minutes by redeploying the previous image.
A Terraform apply can delete a database. Different risk, different gate.

The apply job also applies the *saved plan file* that was reviewed, not a fresh plan.
Re-planning after approval means the reviewer approved one set of changes and a different
set gets applied.

---

## Security

| Control | How |
|---|---|
| No static AWS keys in CI | GitHub OIDC; the role trust policy pins repo *and* branch/environment, so a fork PR cannot assume it |
| Database credentials | Generated by Terraform, written to Secrets Manager, injected by ECS at task start via `secrets`. Never in an env var in the task definition, never in the repo, never typed by a human |
| Least privilege, two roles | Execution role (pull image, read *this one* secret, write logs) is separate from the task role (near-empty; the app talks to Postgres and nothing else in AWS) |
| No `iam:PassRole` on `*` | Scoped to the two ECS roles, with an `iam:PassedToService` condition |
| Network isolation | Chained security groups referencing each other by ID, never by CIDR — task IPs change every deploy, group membership does not. Data subnets have no route to the internet |
| Database egress | The RDS security group has **no** egress rules at all |
| Encryption | RDS storage, Secrets Manager, ECR and the state bucket all encrypted; prod uses a customer-managed KMS key with rotation |
| TLS enforced | Bucket policy denies any request with `aws:SecureTransport=false`; ALB uses a TLS 1.3 policy when a certificate is configured |
| Container hardening | Multi-stage build (no compiler in the runtime image), non-root UID 10001, read-only root filesystem in prod |
| Supply chain | `pip-audit` on dependencies, Trivy on the image, immutable ECR tags, a CycloneDX SBOM archived per release |
| Request tracing | Every request carries an `X-Request-Id` through logs, so an incident can be reconstructed |

**Known gaps**, stated rather than hidden:

- The staging ALB serves plain HTTP. It has no domain, so there is no certificate to
  attach. Production takes `certificate_arn` and redirects 80 → 443 when it is set.
- Staging tasks run in public subnets with a public IP (still ALB-only ingress). That is
  the cost of skipping the NAT gateway, and it is why prod does not do it.
- Secrets Manager rotation is not enabled. The secret is stored in the JSON shape RDS's
  own rotation Lambda expects, so switching it on is configuration, not a rewrite.
- `tfsec` runs in `soft_fail` mode. It should be a hard gate once the existing findings
  are triaged; making it blocking on day one with a backlog just teaches people to skip it.

---

## Cost

Ballpark for `ap-south-1`, staging as configured:

| | monthly |
|---|---|
| ALB | ~$18 (the floor; it is the largest fixed cost) |
| Fargate, 1 task, 0.25 vCPU/0.5 GB, Spot | ~$3 |
| RDS `db.t3.micro`, 20 GB gp3 | $0 under free tier, ~$13 after |
| NAT gateway | **$0** — deliberately not provisioned |
| CloudWatch logs, 7-day retention | ~$1 |
| **Total** | **~$22/month**, or ~$35 once free tier lapses |

What the configuration actually does about cost:

- **No NAT gateway in staging.** The single largest saving available (~$32/month). Tasks
  run in public subnets with ALB-only ingress instead.
- **S3 gateway endpoint** — free, and keeps ECR layer pulls (S3 objects underneath) off
  the NAT in production, where NAT data processing is billed per GB.
- **Fargate Spot in staging** — ~70% cheaper. A reclaim event in staging is free practice
  for the same event in production.
- **`gp3` over `gp2`** — same price at 20 GB, but 3000 baseline IOPS instead of 60.
- **Graviton in production** (`db.t4g.small`) — ~10% cheaper than `t3` and faster on
  Postgres. Staging stays on `t3.micro` only because that is what free tier covers.
- **Log retention set explicitly everywhere.** The CloudWatch default is *never expire*,
  which is a bill that grows forever and is the single most common AWS cost leak.
- **ECR lifecycle policy** — keeps 15 tagged images, expires untagged layers after 3 days.
  CI pushes an image per merge; without this the repository grows without bound.
- **Storage autoscaling with a ceiling** (`max_allocated_storage`), so a runaway table
  does not take the service down, and also does not silently grow to 200 GB.
- **Container Insights is a variable**, defaulted on. It bills per metric and is the kind
  of thing that should be a conscious choice.

---

## Backups and recovery

| | staging | prod |
|---|---|---|
| Automated snapshots | 7 days | 30 days |
| Point-in-time recovery | within the retention window | within the retention window |
| Final snapshot on destroy | skipped | taken |
| Deletion protection | off | on |
| Terraform state | S3 versioning, 90 days of history | same |

Backup window is 18:00–19:00 UTC (23:30 IST) — off-peak for the traffic pattern I assumed —
and the maintenance window is deliberately non-overlapping.

`backup_retention_days` has a validation rule rejecting `0`, because setting it to zero
also silently disables point-in-time recovery. That is an easy mistake to make and an
expensive one to discover.

Restore procedure is in [`docs/runbook.md`](docs/runbook.md).

---

## Monitoring and logging

Two parallel implementations, deliberately:

**In AWS** (`terraform/modules/observability`) — CloudWatch metrics for the ALB, ECS and
RDS; application logs shipped by the `awslogs` driver; a metric filter turning `ERROR`
log lines into a metric; 10 alarms on an SNS topic; and two dashboards.

**Locally** (`monitoring/`) — Prometheus scraping the app's own `/metrics`, plus
`node-exporter`, `cadvisor` and `postgres_exporter`; Loki + Promtail for logs;
Alertmanager; and two provisioned Grafana dashboards.

The local stack is not a toy. CloudWatch cannot compute a p99 from the application's own
histogram — it only stores what the ALB reports — and being able to run the entire
pipeline on a laptop means dashboards and alert rules can be iterated on before they cost
anything. The alert rules in both places are deliberately kept equivalent.

### The dashboards

**Service Health** — laid out in triage order: traffic → errors → latency → capacity.
Six SLI tiles across the top, then request rate by status class, error rate *as a
percentage*, latency percentiles (p50 next to p99, because p99 alone cannot distinguish
"everything got slower" from "one bad endpoint"), p95 per route, and a live log panel.

**Infrastructure & Database** — host and container CPU/memory/disk/network, then
PostgreSQL: connections by state, transaction rate, cache hit ratio, rows processed.

Deliberate choices in both: no dual-axis panels anywhere (two y-scales let you slide
unrelated series until they appear to correlate); error rate is a ratio, never a raw
count; status colours are reserved for state and never reused as a series colour; the
series palette was checked for colour-blind separation rather than picked by eye.

### Metric cardinality

The route *template* is the metric label, never the raw path — `/tasks/{task_id}` is one
series, `/tasks/1`, `/tasks/2`, … would be one series per task and would eventually take
Prometheus down. Unmatched paths (scanner traffic) all collapse into a single `unmatched`
series. There is a test that fails if this regresses.

---

## The pipeline

```
 PR opened ──► ci.yml
               lint · unit · integration (real Postgres) · pip-audit
               Trivy image scan · terraform fmt/validate/tfsec
                     │
 merge to main ──► cd.yml
                   re-test the merge commit
                     │
                   build once ──► Trivy gate ──► SBOM ──► push to ECR
                     │
                   deploy staging ──► smoke test ──► rollback on failure
                     │
                   ⏸  environment: production  (required reviewers)
                     │
                   deploy production ──► smoke test ──► rollback on failure
                     │
                   Slack notification
```

Details worth pointing at:

- **The merge commit is retested.** CI tested the PR branch; what ships is the merge
  result, which nobody has tested yet.
- **The image is built once**, scanned, and that exact image is pushed. Building a second
  time for the push would risk shipping bytes the scanner never looked at.
- **Production promotes the tag staging ran**, verified present in ECR — it does not
  rebuild from source. A rebuild from the same commit can produce different bytes.
- **Trivy runs twice**: an informational pass that uploads SARIF to the Security tab, and
  a gate that fails only on HIGH/CRITICAL *with a fix available*. Failing on unfixable
  base-image CVEs just teaches people to add `--exit-code 0`.
- **The smoke test checks the reported build SHA**, not just a 200. Without that, a
  deploy that silently rolled back still "passes" — the old version answers `/readyz`
  perfectly well.
- **Rollback is explicit**, on top of the ECS deployment circuit breaker, and the previous
  task definition ARN is captured *before* anything changes.
- **`cancel-in-progress` is false** for deploys and true for CI. Cancelling a half-finished
  ECS rollout leaves the service in a mixed state; cancelling a stale test run is free.

---

## What I would build next

In the order I would actually do it:

1. **Alembic migrations as a pre-deploy ECS task.** Today the app calls `create_all()`
   behind a Postgres advisory lock at boot — which works, and the lock is there because
   two workers racing produced a real `UniqueViolation` while I was building this (see
   `CHALLENGES.md`). But application containers should not run DDL at all.
2. **A canary deployment step.** The infrastructure is already in place — the ALB has a
   second, unused target group specifically so a blue/green cutover does not require
   creating resources at the moment you most want to move fast.
3. **OpenTelemetry tracing.** Logs already carry `X-Request-Id` end to end and the Grafana
   Loki datasource extracts it as a derived field, so the correlation point exists; there
   is just no trace backend behind it yet.
4. **Secrets Manager rotation**, which is configuration rather than a rewrite given the
   secret's JSON shape.
5. **`tfsec` as a hard gate**, once the current findings are triaged.

---

## Documents

- [`CHALLENGES.md`](CHALLENGES.md) — what broke while building this and how it was fixed
- [`docs/runbook.md`](docs/runbook.md) — incident procedures and restore steps
- [`docs/demo.md`](docs/demo.md) — walkthrough script
