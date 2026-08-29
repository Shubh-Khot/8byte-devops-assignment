#!/usr/bin/env bash

set -euo pipefail

CLUSTER="${1:?usage: deploy.sh <cluster> <service> <image>}"
SERVICE="${2:?usage: deploy.sh <cluster> <service> <image>}"
IMAGE="${3:?usage: deploy.sh <cluster> <service> <image>}"

echo "Deploying $IMAGE to $SERVICE"

PREVIOUS=$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text)

echo "Current task definition: $PREVIOUS"

aws ecs describe-task-definition --task-definition "$PREVIOUS" \
  --query 'taskDefinition' > /tmp/taskdef.json

jq --arg image "$IMAGE" '
  .containerDefinitions[0].image = $image
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
        .compatibilities, .registeredAt, .registeredBy)
' /tmp/taskdef.json > /tmp/taskdef-new.json

NEW=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/taskdef-new.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)

echo "New task definition: $NEW"

aws ecs update-service \
  --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$NEW" > /dev/null

echo "Waiting for the service to stabilise"
if aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"; then
  echo "Deployed $IMAGE"
  exit 0
fi

echo "Rollout failed, rolling back to $PREVIOUS" >&2
aws ecs update-service \
  --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$PREVIOUS" > /dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
echo "Rolled back" >&2
exit 1
