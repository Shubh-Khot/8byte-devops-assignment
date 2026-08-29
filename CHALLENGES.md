# Challenges and resolutions

Problems hit while building and deploying this stack, with the actual errors
and what fixed them.

## 1. An SCP blocked the whole build on the first AWS account

**Symptom.** `terraform plan` worked, but every real call failed:

```
An error occurred (UnauthorizedOperation) when calling the DescribeVpcs
operation: ... with an explicit deny in a service control policy:
arn:aws:organizations::...:policy/.../service_control_policy/p-fpli5i1p
```

**Diagnosis.** Two separate blockers. The service control policy denied every
call in `ap-south-1` while allowing `us-east-1`, so the account was region
locked. And even in the allowed region, the IAM group granted EC2, RDS and VPC
but **not** ECS, ECR or Secrets Manager:

```
ecs:ListClusters -> no identity-based policy allows the ecs:ListClusters action
```

An SCP overrides IAM, so no permission grant could fix the first half.

**Resolution.** Moved to an account with no organisation attached. Worth
knowing that `terraform plan` succeeded throughout: plan touched none of the
denied APIs, so it gave a false sense that the credentials were sufficient.

## 2. GitHub changed the OIDC subject format

**Symptom.** Every pipeline run failed at the first AWS step:

```
Could not assume role with OIDC: Not authorized to perform
sts:AssumeRoleWithWebIdentity
```

The trust policy looked correct and matched every example in the docs.

**Diagnosis.** CloudTrail showed the subject STS actually received:

```
repo:OWNER@140479984/REPO@1349921486:ref:refs/heads/main
```

GitHub now embeds immutable numeric owner and repository ids in the `sub`
claim, so a deleted and re-registered name cannot inherit a role. The trust
policy matched only the old `repo:OWNER/REPO:...` form.

**Resolution.** The condition now accepts both forms. A second trap sits next
to this one: jobs that declare a GitHub Environment send
`...:environment:prod`, not `...:ref:refs/heads/main`, so a policy pinned to a
branch rejects exactly the deployment jobs it was meant to allow.

## 3. `PowerUserAccess` cannot create IAM roles

**Symptom.** The deploy role could create everything except the two IAM roles
the ECS task definition needs.

**Diagnosis.** `PowerUserAccess` grants every service except IAM writes. The
`app` module creates an execution role and a task role, so apply from CI would
have failed on `iam:CreateRole`.

**Resolution.** An inline policy on the deploy role allowing role management,
scoped to `role/<name_prefix>-*` rather than `*`.

## 4. Seven CVEs in a transitive dependency

**Symptom.** `pip-audit` failed CI with seven advisories against
`starlette 0.41.3`, including an unauthenticated denial of service in
`FileResponse` range parsing.

**Diagnosis.** Starlette was pinned transitively by FastAPI 0.115, which caps
it below 0.42. Bumping Starlette alone was not possible.

**Resolution.** A coordinated upgrade to FastAPI 0.141 and Starlette 1.6, then
re-running the suite to confirm nothing broke.

## 5. A fixable HIGH in the base image

**Symptom.** Trivy failed the build on `CVE-2026-14456` in `openssl`,
`libssl3t64` and `openssl-provider-legacy`, inherited from `python:3.12-slim`.

**Resolution.** `apt-get upgrade` in the runtime stage takes openssl to
`3.5.7-1~deb13u2` and the image to zero fixable HIGH or CRITICAL findings. The
scan gate uses `--ignore-unfixed`, because failing on CVEs with no available
patch only teaches people to disable the gate.

## 6. A container health check that could never pass

**Symptom.** The ECS task definition health check ran
`curl -f http://localhost:8000/readyz`.

**Diagnosis.** `python:3.12-slim` does not ship `curl`. The check would fail
every time, ECS would kill the container, and the service would crash loop —
and none of that shows up in `terraform validate` or `terraform plan`.

**Resolution.** Removed the container-level check and relied on the ALB target
group, which already polls `/readyz`. Installing curl or using a Python
one-liner would also have worked.

## 7. The whole secret injected instead of one field

**Symptom.** Caught in review rather than at runtime: the task definition used
`valueFrom = var.db_secret_arn`.

**Diagnosis.** RDS's managed secret is a JSON document,
`{"username": "...", "password": "..."}`. Without a key selector, ECS injects
the entire document as `DB_PASSWORD` and the application cannot connect.

**Resolution.** `"${var.db_secret_arn}:password::"`. The two trailing colons
are the empty version-stage and version-id fields.

## 8. CloudWatch dimensions need the ARN suffix, not the ARN

**Symptom.** The `app` module exported `alb_arn` and `target_group_arn`, while
the monitoring module needed `alb_arn_suffix` and `target_group_arn_suffix`.

**Diagnosis.** CloudWatch metric dimensions use the suffix form
(`app/name/hash`). Passing a full ARN is accepted without error — the alarms
and dashboard widgets simply render empty forever.

**Resolution.** Added the two `arn_suffix` outputs.

## 9. An action version that never existed

**Symptom.** `Unable to resolve action aquasecurity/trivy-action@0.28.0`.

**Diagnosis.** That project's release tags are `v`-prefixed. `0.28.0` has
never existed; the current tag is `v0.36.0`.

## 10. Where cost was traded against isolation

Not a bug, but the decision that took longest. A NAT gateway is about $32 a
month per availability zone and is the largest line item in the stack. Without
one, Fargate tasks in private subnets cannot reach ECR to pull their own image,
so the service cannot start at all.

| Option | Cost | Trade |
|---|---|---|
| NAT per AZ | ~$64/mo (2 AZ) | correct, and hard to justify at this size |
| One shared NAT | ~$32/mo | one AZ becomes a dependency for all egress |
| Interface VPC endpoints | ~$29/mo | comparable cost, more moving parts |
| Tasks in public subnets | $0 | weaker isolation |

One shared NAT in both environments, with tasks and the database private.
Putting staging's tasks in public subnets would have saved the $32 outright,
but then staging stops being a rehearsal for production, and the difference
would be exactly the part carrying the security risk.
