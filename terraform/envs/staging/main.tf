# Staging.
#
# Same modules as production, different dials. The point of an environment
# root this thin is that "how does staging differ from prod?" is answerable by
# diffing two tfvars files instead of reading two piles of Terraform.
#
# The deliberate cost cuts here, all reversed in prod:
#   - no NAT gateway; tasks run in public subnets    (~$32/month)
#   - single-AZ RDS                                  (~50% of the DB bill)
#   - 1 task minimum instead of 2
#   - 7 day log retention instead of 30

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Environment = var.environment
    CostCentre  = "engineering"
  }
}

# Looking AZs up beats hardcoding them: AZ names are per-account aliases, so
# "ap-south-1a" is not the same physical zone in two different accounts.
#
# count is here because some locked-down accounts deny ec2:DescribeAvailabilityZones
# via an SCP. Setting var.availability_zones explicitly skips the call entirely
# rather than failing the plan on a permission the stack does not really need.
data "aws_availability_zones" "available" {
  count = length(var.availability_zones) > 0 ? 0 : 1
  state = "available"
}

locals {
  # Two AZs is the minimum the ALB and the RDS subnet group accept.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available[0].names, 0, 2)
}

module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs

  # No NAT in staging. Tasks sit in public subnets with a public IP so they
  # can reach ECR, and are still firewalled to ALB-only ingress.
  enable_nat_gateway = false
  enable_s3_endpoint = true
  enable_flow_logs   = false

  tags = local.tags
}

module "security" {
  source = "../../modules/security"

  name_prefix   = local.name_prefix
  vpc_id        = module.network.vpc_id
  app_port      = var.app_port
  ingress_cidrs = var.alb_ingress_cidrs

  tags = local.tags
}

module "database" {
  source = "../../modules/database"

  name_prefix       = local.name_prefix
  subnet_ids        = module.network.data_subnet_ids
  security_group_id = module.security.database_security_group_id

  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false

  backup_retention_days = 7

  # Staging is rebuilt often; the guard rails that protect prod just get in
  # the way here. Both of these are false in prod.
  skip_final_snapshot         = true
  deletion_protection         = false
  secret_recovery_window_days = 0

  performance_insights_enabled = true
  enhanced_monitoring_interval = 60

  tags = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix  = local.name_prefix
  environment  = var.environment
  service_name = var.service_name

  vpc_id                  = module.network.vpc_id
  public_subnet_ids       = module.network.public_subnet_ids
  private_subnet_ids      = module.network.private_subnet_ids
  alb_security_group_id   = module.security.alb_security_group_id
  tasks_security_group_id = module.security.tasks_security_group_id

  # Follows directly from enable_nat_gateway = false above.
  tasks_in_public_subnets = true

  image_tag   = var.image_tag
  app_port    = var.app_port
  task_cpu    = 256
  task_memory = 512

  desired_count = 1
  min_capacity  = 1
  max_capacity  = 3

  # Staging runs entirely on Spot. A reclaim event here is a free rehearsal
  # for the same event in production.
  on_demand_base   = 0
  on_demand_weight = 0
  spot_weight      = 1

  database_host       = module.database.address
  database_port       = module.database.port
  database_name       = module.database.database_name
  database_username   = var.db_username
  database_secret_arn = module.database.secret_arn

  log_level          = "DEBUG"
  log_retention_days = 7

  ecr_keep_images  = 10
  ecr_force_delete = true

  tags = local.tags
}

module "observability" {
  source = "../../modules/observability"

  name_prefix = local.name_prefix
  region      = var.region

  alb_arn_suffix          = module.ecs.alb_arn_suffix
  target_group_arn_suffix = module.ecs.target_group_arn_suffix
  cluster_name            = module.ecs.cluster_name
  service_name            = module.ecs.service_name
  db_instance_identifier  = module.database.identifier
  log_group_name          = module.ecs.log_group_name

  alert_emails      = var.alert_emails
  slack_webhook_url = var.slack_webhook_url

  # Looser than prod on purpose. Staging alarms that fire constantly are how
  # a team learns to ignore alarms.
  error_count_threshold         = 20
  latency_p99_threshold_seconds = 3

  tags = local.tags
}
