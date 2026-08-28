# Runbook

For the person on call at 3am. Ordered by what you should do first, not by what is
most interesting.

## Where to look

| | |
|---|---|
| Service health dashboard | `taskapi-<env>-service-health` in CloudWatch |
| Platform dashboard | `taskapi-<env>-platform` |
| Application logs | `/ecs/taskapi-<env>/task-api` |
| Database logs | RDS console → `taskapi-<env>-postgres` → Logs |
| Alerts | SNS topic `taskapi-<env>-alerts` |

Triage order on the service dashboard is left to right, top to bottom:
**traffic → errors → latency → capacity**. If traffic is zero, nothing downstream matters
and the problem is in front of the ALB.

---

## Alert: `unhealthy-targets`

Tasks are failing `/readyz` and have been pulled from the target group.

```bash
ENV=staging
aws ecs describe-services --cluster taskapi-$ENV-cluster --services task-api \
  --query 'services[0].{running:runningCount,desired:desiredCount,deployments:deployments[].{status:status,rollout:rolloutState}}'
```

1. **Is it a deploy?** If `rolloutState` is `IN_PROGRESS` or `FAILED`, the circuit breaker
   is probably already rolling back. Watch it rather than intervening.
2. **Is it the database?** `/readyz` returns 503 when Postgres is unreachable, and it is
   the most common cause. Check the `rds-cpu-high` and `rds-connections-high` alarms and
   the platform dashboard.
3. **Is it one task or all of them?** One task is a bad host — stop it and let ECS
   replace it. All tasks at once points at a shared dependency, which means the database.

```bash
# what the task itself says
aws logs tail /ecs/taskapi-$ENV/task-api --since 15m --filter-pattern '{ $.level = "ERROR" }'

# shell into a running task
aws ecs execute-command --cluster taskapi-$ENV-cluster --task <task-id> \
  --container task-api --interactive --command "/bin/sh"
```

---

## Alert: `alb-5xx` or `application-errors`

```bash
aws logs tail /ecs/taskapi-$ENV/task-api --since 30m --follow \
  --filter-pattern '{ $.status >= 500 }'
```

Every log line carries `request_id`. Take one from a failing request and follow it:

```bash
aws logs filter-log-events --log-group-name /ecs/taskapi-$ENV/task-api \
  --filter-pattern '{ $.request_id = "abc123def456" }'
```

If the errors started at a deployment boundary, compare the `build` field in the logs
against the previous release and roll back (below). If they did not, the cause is
usually downstream — the database, or a change in traffic shape.

---

## Alert: `alb-latency-p99`

Check p50 alongside p99 on the dashboard before anything else:

- **p50 up as well** — everything is slower. Look at capacity: task CPU, RDS CPU, and
  whether autoscaling has hit `max_capacity`.
- **p50 flat, p99 up** — one endpoint or one query. Use the *slowest endpoints* Logs
  Insights widget on the platform dashboard, then check RDS Performance Insights for the
  matching query.

---

## Rolling back a deployment

The pipeline rolls back automatically when a smoke test fails. To do it by hand:

```bash
ENV=staging
# list recent revisions, newest first
aws ecs list-task-definitions --family-prefix taskapi-$ENV-task-api \
  --sort DESC --max-items 5

aws ecs update-service --cluster taskapi-$ENV-cluster --service task-api \
  --task-definition taskapi-$ENV-task-api:<previous-revision> --force-new-deployment

aws ecs wait services-stable --cluster taskapi-$ENV-cluster --services task-api
./scripts/smoke-test.sh "$(terraform -chdir=terraform/envs/$ENV output -raw app_url)"
```

Rolling back the *image* does not roll back a database migration. If the release included
a schema change, check that the previous version can still read the current schema before
doing this.

---

## Database restore

**Point-in-time recovery**, within the retention window (7 days staging, 30 prod). This
creates a *new* instance; it does not overwrite the existing one.

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier taskapi-prod-postgres \
  --target-db-instance-identifier taskapi-prod-postgres-restored \
  --restore-time 2026-08-28T14:30:00Z \
  --db-subnet-group-name taskapi-prod-db \
  --vpc-security-group-ids <database-sg-id> \
  --no-publicly-accessible
```

Then verify the restored data *before* cutting over, and cut over by updating the
`DB_HOST` environment variable in the task definition — not by renaming instances.

**From a snapshot:**

```bash
aws rds describe-db-snapshots --db-instance-identifier taskapi-prod-postgres \
  --query 'sort_by(DBSnapshots,&SnapshotCreateTime)[-5:].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

Restore time for a 20 GB instance is roughly 10–20 minutes. Budget for that in any
incident where restore is on the table — it is usually longer than people expect.

---

## Recovering Terraform state

The state bucket is versioned specifically for this.

```bash
BUCKET=$(terraform -chdir=terraform/bootstrap output -raw state_bucket)

aws s3api list-object-versions --bucket "$BUCKET" --prefix staging/terraform.tfstate \
  --query 'Versions[:5].[VersionId,LastModified,Size]' --output table

aws s3api get-object --bucket "$BUCKET" --key staging/terraform.tfstate \
  --version-id <version-id> restored.tfstate

terraform -chdir=terraform/envs/staging state push restored.tfstate
```

If a lock is stuck after a cancelled run, confirm nothing is actually running first, then
`terraform force-unlock <lock-id>`. Force-unlocking a live apply corrupts state.

---

## Rotating the database password

```bash
SECRET=$(terraform -chdir=terraform/envs/prod output -raw database_secret_name)
aws secretsmanager get-secret-value --secret-id "$SECRET" --query SecretString --output text
```

ECS reads the secret **at task start**, so changing it does not affect running tasks and
does not take effect until a new deployment:

```bash
aws ecs update-service --cluster taskapi-prod-cluster --service task-api --force-new-deployment
```

Change the password in RDS *and* the secret together — updating only one locks the
application out at the next deploy.

---

## Scaling up in a hurry

```bash
# raise the autoscaling ceiling
aws application-autoscaling register-scalable-target \
  --service-namespace ecs --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/taskapi-prod-cluster/task-api \
  --min-capacity 4 --max-capacity 20
```

If the bottleneck is the database rather than the application, more tasks make it worse —
each one opens its own connection pool. Check `DatabaseConnections` on the platform
dashboard before scaling out.
