# Task API

A small FastAPI service deployed to AWS ECS Fargate, with Terraform for the
infrastructure, GitHub Actions for the pipeline, and both CloudWatch and a
local Prometheus stack for monitoring.

The application itself is deliberately small: a CRUD API over a `tasks` table.
The point of the repository is everything around it.

## Layout

```
app/                    FastAPI service and tests
terraform/
  bootstrap/            state bucket, ECR repository, GitHub OIDC role
  modules/
    network/            VPC, subnets, NAT, routing
    security/           the three security groups
    database/           RDS Postgres
    app/                ALB, ECS cluster, service, task definition, IAM
    monitoring/         CloudWatch alarms, dashboard, SNS topic
  envs/
    staging/            same modules, smaller instances
    prod/               same modules, multi-AZ and deletion protection
.github/workflows/      ci.yml, cd.yml, infra.yml
monitoring/             Prometheus, Alertmanager, Loki, Promtail, Grafana
scripts/                deploy, smoke test, load generator, teardown
```

## Running it locally

You need Docker and Make.

```
make up          # API on http://localhost:8000/docs, Postgres alongside
make test        # 17 tests against a real Postgres in Docker
make lint        # ruff check and format check
make down        # stop, keep the data
```

For the full monitoring stack:

```
make monitoring  # adds Prometheus, Grafana, Loki, Alertmanager, exporters
make load        # 60 seconds of traffic so the dashboards have something
```

Grafana is on http://localhost:3000 (admin/admin) with two dashboards already
provisioned. Prometheus is on :9090, Alertmanager on :9093.

To watch an alert fire end to end:

```
make load-errors   # sends traffic to /boom, which returns 500 on purpose
```

`HighErrorRate` moves to pending, then firing, then reaches Alertmanager.

## Deploying to AWS

### Once per account

```
cd terraform/bootstrap
terraform init
terraform apply \
  -var state_bucket_name=your-unique-bucket-name \
  -var github_repository=your-org/your-repo
```

This creates the S3 bucket for Terraform state, the ECR repository, and the
IAM role GitHub Actions assumes. Note the two outputs.

### Per environment

```
cd terraform/envs/staging
terraform init -backend-config=bucket=your-unique-bucket-name
terraform apply
```

Then the same for `terraform/envs/prod`. The first apply will fail to start
tasks until an image exists in ECR, which is what the pipeline pushes.

### Pipeline secrets

In the GitHub repository, add two secrets:

- `AWS_ROLE_ARN`: the `github_actions_role_arn` output from bootstrap
- `TF_STATE_BUCKET`: the bucket name

Create two GitHub Environments, `staging` and `production`, and add a required
reviewer to `production`. That reviewer prompt is the production gate.

### Tearing it down

```
cd terraform/envs/staging && terraform destroy
```

Production has `deletion_protection = true` on the database and the load
balancer, so that has to be turned off in `terraform.tfvars` and applied
before a destroy will go through. That is deliberate.

## Decisions worth explaining

**ECS Fargate, not EKS or EC2.** One service does not justify a Kubernetes
control plane at $73/month plus the operational surface. Fargate has no hosts
to patch. The tradeoff is less control and a higher per-vCPU price; at this
size that trade is clearly worth it.

**Two subnet tiers.** Public subnets hold only the load balancer. Everything
else, tasks and database, sits in private subnets with no route to the
internet except through one NAT gateway. A second NAT would remove a single
point of failure but costs another $32/month, which is not worth it for
staging or for a demo.

**Security groups reference each other, never CIDRs.** The database accepts
5432 only from the application security group, and the application accepts
traffic only from the load balancer's. Nothing has to be rewritten when
subnets change.

**The database password is never in Terraform.** RDS generates it with
`manage_master_user_password` and stores it in Secrets Manager. Terraform
only passes the secret ARN to the task definition; ECS injects the value at
container start. The password is not in state, not in the repo, and not in
the task definition.

**`/healthz` and `/readyz` mean different things.** Liveness never touches
the database, because if it did, a brief database blip would restart every
task at once. Readiness does check it, and returns 503 so the load balancer
takes that task out of rotation without killing it.

**Terraform does not deploy images.** The ECS service has
`ignore_changes = [task_definition]`, and the pipeline updates the image with
the AWS CLI. Without that, every `terraform apply` would revert the running
version to whatever the code says. Infrastructure changes and application
deploys move at different speeds.

**Environments differ by variables, not by copies.** `staging` and `prod`
have identical `main.tf`. Everything that differs lives in
`terraform.tfvars`: instance class, multi-AZ, backup retention, task count,
deletion protection.

## Security

What is in place:

- No long-lived AWS keys. GitHub Actions authenticates by OIDC, and the trust
  policy is pinned to this repository.
- Database in private subnets, `publicly_accessible = false`, reachable only
  from the application security group.
- Storage encrypted at rest on RDS; state bucket encrypted and versioned with
  public access blocked.
- The container runs as a non-root user.
- CI fails on HIGH and CRITICAL image vulnerabilities that have a fix, and
  audits Python dependencies against the advisory database.

Known gaps, and why:

- **HTTP, not HTTPS.** TLS needs a domain and an ACM certificate, which this
  account does not have. The listener would become 443 with a redirect from
  80; it is a small change, not a design change.
- **The pipeline role has PowerUserAccess.** Correct would be a policy scoped
  to exactly the services this stack touches. That work is real and was not
  the best use of the time available here.
- **No WAF.** Rate limiting and managed rule groups would be the next thing
  to add in front of the load balancer.

## Cost

Rough monthly figures for `ap-south-1`, staging:

| Item | Cost |
|---|---|
| Fargate, 1 task at 0.25 vCPU / 0.5 GB | ~$9 |
| ALB | ~$18 |
| NAT gateway | ~$32 |
| RDS `db.t4g.micro`, single AZ | ~$13 |
| Storage, logs, ECR | ~$5 |
| **Total** | **~$77** |

Production roughly doubles that: two tasks and a multi-AZ database.

The NAT gateway is the single largest line item and buys one thing, outbound
internet for tasks in private subnets. Interface VPC endpoints would remove
the need for it, but four of them cost about the same and add more moving
parts, so it stays.

## Monitoring

**In AWS.** Seven CloudWatch alarms cover load balancer 5xx, p95 latency,
unhealthy targets, ECS CPU and memory, and RDS CPU and free storage. They
notify an SNS topic. One dashboard shows traffic, latency, ECS utilisation
and database health. Container logs go to CloudWatch Logs with retention set
per environment.

**Locally.** Prometheus scrapes the app, Postgres, cAdvisor and
node-exporter. Nine alert rules go to Alertmanager. Loki and Promtail collect
the container logs, and two Grafana dashboards are provisioned from the
repository, so they come up populated rather than blank.

The application emits JSON logs with a request id on every line, taken from
`X-Request-Id` when a proxy already set one. Both Loki and CloudWatch Logs
Insights parse that without extra configuration.

Metric labels use the route template, so `/tasks/{task_id}` is one series
rather than one series per task id.

## Pipeline

**ci.yml**, on every pull request: lint, tests against a real Postgres
service container, dependency audit, image build and Trivy scan, and
`terraform validate` across every root and module.

**cd.yml**, on merge to main: build one image, push it to ECR tagged with the
commit sha, deploy to staging, smoke test it, wait for a reviewer to approve
production, deploy the same image, smoke test again. `scripts/deploy.sh`
rolls back to the previous task definition if the service does not stabilise.

**infra.yml**: plans both environments on any pull request touching
`terraform/`, and applies one environment on manual dispatch.

## Known issues

`CHALLENGES.md` records the problems hit while building this, including two
real bugs: a schema-creation race between workers, and a false critical alert
caused by a gauge that only updated on request.
