#!/usr/bin/env bash

set -euo pipefail

ENV="${1:?usage: teardown.sh <staging|prod>}"
DIR="infra/envs/${ENV}"
REGION="${AWS_REGION:-ap-south-1}"

[ -d "$DIR" ] || { echo "No such environment: $ENV" >&2; exit 1; }

if [ "$ENV" = "prod" ]; then
  echo "This destroys PRODUCTION, including the database."
  read -r -p "Type the environment name to confirm: " confirm
  [ "$confirm" = "prod" ] || { echo "Aborted."; exit 1; }
fi

PREFIX="taskapi-${ENV}"

echo "==> Disabling RDS deletion protection"
if aws rds describe-db-instances --db-instance-identifier "${PREFIX}-postgres" \
     --region "$REGION" >/dev/null 2>&1; then
  aws rds modify-db-instance \
    --db-instance-identifier "${PREFIX}-postgres" \
    --no-deletion-protection --apply-immediately \
    --region "$REGION" >/dev/null
  echo "    waiting for the modification to land"
  aws rds wait db-instance-available \
    --db-instance-identifier "${PREFIX}-postgres" --region "$REGION"
else
  echo "    no instance found, skipping"
fi

echo "==> Disabling ALB deletion protection"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "${PREFIX}-alb" \
  --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 modify-load-balancer-attributes --load-balancer-arn "$ALB_ARN" \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region "$REGION" >/dev/null
fi

echo "==> terraform destroy"
terraform -chdir="$DIR" destroy

echo
echo "Done. Worth checking by hand, because these outlive the stack:"
echo "  - the final RDS snapshot (prod keeps one; it is not free)"
echo "  - CloudWatch log groups, if retention had not expired them yet"
echo "  - the Terraform state bucket, which is intentionally never destroyed"
echo "  - the shared ECR repository, which belongs to bootstrap, not to an environment"
