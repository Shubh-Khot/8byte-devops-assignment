# Task API on ECS Fargate

A small FastAPI service deployed to AWS ECS Fargate, with Terraform for the
infrastructure, GitHub Actions for build and deployment, and CloudWatch for
metrics, logs and alarms across two environments.

## Attribution

- The **application** is FastAPI's official SQL databases tutorial, taken from
  https://fastapi.tiangolo.com/tutorial/sql-databases/. The models and CRUD
  routes are unmodified. Only the database connection (Postgres from the
  environment instead of a local SQLite file) and the `/healthz` and `/readyz`
  endpoints were added, because the load balancer needs a health check.
- The **infrastructure code** was written with AI assistance.

## Layout

```
app/                      FastAPI service and tests
infra/
  bootstrap/              state bucket, ECR repository, GitHub OIDC role
  modules/
    network/              VPC, subnets, NAT, routing
    security/             ALB, ECS and RDS security groups
    database/             RDS Postgres
    app/                  ALB, ECS cluster, service, task definition, IAM
    monitoring/           CloudWatch alarms, two dashboards, SNS topic
  envs/
    staging/              same modules, smaller instances
    prod/                 same modules, multi-AZ and deletion protection
.github/workflows/        ci.yml, cd.yml
scripts/                  deploy, smoke test, teardown
```

## Running it locally

Requires Docker and Make.

```
make up      # API on http://localhost:8000/docs, Postgres alongside
make test    # 8 tests against a real Postgres in Docker
make lint    # ruff check and format check
make down    # stop, keep the data
```

## Deploying

### Once per account

```
cd infra/bootstrap
terraform init
terraform apply \
  -var aws_region=ap-south-1 \
  -var state_bucket_name=<globally-unique-bucket> \
  -var ecr_repository_name=taskapi \
  -var github_repository=<owner>/<repo> \
  -var github_owner_id=<gh api user --jq .id> \
  -var github_repository_id=<gh api repos/OWNER/REPO --jq .id>
```

This creates the S3 state bucket, the ECR repository, the GitHub OIDC
provider and the role the pipeline assumes. Note the outputs.

### Per environment

```
cd infra/envs/staging
terraform init -backend-config=bucket=<your-bucket>
terraform apply
```

Then the same for `infra/envs/prod`. The first apply cannot start tasks until
an image exists in ECR, which is what the pipeline pushes.

### Pipeline setup

Repository secrets: `AWS_ROLE_ARN` and `TF_STATE_BUCKET`. Create GitHub
Environments named `staging` and `prod`, and add a required reviewer to
`prod`. That reviewer prompt is the production gate.

## Decisions

**ECS Fargate rather than EKS or EC2.** One service does not justify a
Kubernetes control plane at $73/month plus the operational surface. Fargate
has no hosts to patch. The trade is less control and a higher per-vCPU price.

**Two subnet tiers.** Public subnets hold only the load balancer. ECS tasks
and RDS sit in private subnets whose only route out is a single NAT gateway.
A second NAT would remove a single point of failure at another $32/month,
which is not worth it at this size.

**Security groups reference each other, never CIDRs.** RDS accepts 5432 only
from the ECS security group, and ECS accepts traffic only from the ALB's.
Nothing needs rewriting when subnets change.

**The database password is never in Terraform.** RDS generates it with
`manage_master_user_password` and stores it in Secrets Manager. Terraform
passes only the secret ARN to the task definition, with a `:password::`
suffix so ECS injects that one JSON key rather than the whole document.

**`/healthz` and `/readyz` differ.** Liveness never touches the database; if
it did, a brief database blip would restart every task at once. Readiness does
check it, so a failing task leaves the load balancer rotation without dying.

**Terraform does not deploy images.** The ECS service sets
`ignore_changes = [task_definition]` and the pipeline updates the image with
the AWS CLI. Without that, every apply would revert the running version.

**Environments differ by variables, not by copies.** `staging` and `prod` have
identical `main.tf`; everything that differs lives in `terraform.tfvars`.

## Security

In place: no long-lived AWS keys (GitHub OIDC with the trust policy pinned to
this repository, including GitHub's immutable owner and repository ids); RDS
private and not publicly accessible; storage encrypted at rest; state bucket
versioned, encrypted and blocked from public access; container runs as a
non-root user; CI fails on fixable HIGH and CRITICAL image vulnerabilities and
audits Python dependencies.

Known gaps: HTTP rather than HTTPS (needs a domain and an ACM certificate);
the deploy role holds `PowerUserAccess` plus a scoped IAM policy rather than
a least-privilege policy; no WAF; a single NAT gateway; no autoscaling;
backups are configured but have never been restore-tested; schema is created
by the application rather than by migrations.

## Monitoring

Five CloudWatch alarms per environment — ECS CPU and memory, ALB 5xx, ALB
unhealthy targets, and RDS CPU — all notifying an SNS topic. Two dashboards:
one for the application (traffic, errors, latency, healthy hosts) and one for
the database and platform. Container logs go to CloudWatch Logs with retention
set per environment.

## Cost

Roughly, per month in ap-south-1 for staging: Fargate ~$9, ALB ~$18, NAT
gateway ~$32, RDS db.t3.micro ~$13, storage and logs ~$5. About $77. Production
roughly doubles it with two tasks and a multi-AZ database. The NAT gateway is
the largest line item and buys outbound internet for private subnets.

## Tearing down

```
cd infra/envs/staging && terraform destroy
```

Production sets `deletion_protection = true`, so that has to be flipped in
`terraform.tfvars` and applied before a destroy will go through.
