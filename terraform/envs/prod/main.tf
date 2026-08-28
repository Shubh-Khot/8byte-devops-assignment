# Production.
#
# Identical module set to staging. Every difference below is a deliberate
# trade of money for either availability or blast-radius reduction:
#
#   - NAT gateway, tasks in private subnets   isolation
#   - Multi-AZ RDS                            automatic failover
#   - 2 task minimum, up to 10                survives an AZ loss
#   - 30 day backups, deletion protection     recovery
#   - customer-managed KMS key                key rotation and revocation
#   - VPC flow logs                           forensics
#   - on-demand capacity, no Spot             no reclaim during peak

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Environment = var.environment
    CostCentre  = "engineering"
    Compliance  = "production"
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
  # Three AZs in production: two survives one AZ failure, three leaves
  # room to lose one while another is being repaired.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available[0].names, 0, 3)
}

module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs

  enable_nat_gateway = true

  # One NAT, not three. A NAT per AZ removes a cross-AZ dependency but triples
  # the standing cost. At this scale a single NAT in one AZ is the honest
  # trade; the variable exists so it flips the day traffic justifies it.
  single_nat_gateway = true

  enable_s3_endpoint      = true
  enable_flow_logs        = true
  flow_log_retention_days = 30

  tags = local.tags
}

module "security" {
  source = "../../modules/security"

  name_prefix     = local.name_prefix
  vpc_id          = module.network.vpc_id
  app_port        = var.app_port
  ingress_cidrs   = var.alb_ingress_cidrs
  certificate_arn = var.certificate_arn

  tags = local.tags
}

module "database" {
  source = "../../modules/database"

  name_prefix       = local.name_prefix
  subnet_ids        = module.network.data_subnet_ids
  security_group_id = module.security.database_security_group_id

  instance_class        = var.db_instance_class
  allocated_storage     = 50
  max_allocated_storage = 200

  # Failover to the standby is automatic and takes 60-120s. Without this, an
  # AZ failure is a restore-from-snapshot exercise measured in hours.
  multi_az = true

  backup_retention_days = 30
  backup_window         = "18:00-19:00" # 23:30 IST, off-peak
  maintenance_window    = "Sun:19:30-Sun:20:30"

  skip_final_snapshot         = false
  deletion_protection         = true
  secret_recovery_window_days = 30

  create_kms_key = true

  performance_insights_enabled = true
  enhanced_monitoring_interval = 30

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

  tasks_in_public_subnets = false # tasks are unreachable from the internet

  image_tag   = var.image_tag
  app_port    = var.app_port
  task_cpu    = 512
  task_memory = 1024

  desired_count = 2
  min_capacity  = 2
  max_capacity  = 10

  # All on-demand. Spot saves ~70% but can be reclaimed with two minutes of
  # notice, and a reclaim wave during peak traffic is not worth the saving.
  on_demand_base   = 2
  on_demand_weight = 1
  spot_weight      = 0

  database_host        = module.database.address
  database_port        = module.database.port
  database_name        = module.database.database_name
  database_username    = var.db_username
  database_secret_arn  = module.database.secret_arn
  database_kms_key_arn = module.database.kms_key_arn

  certificate_arn         = var.certificate_arn
  alb_deletion_protection = true
  access_logs_bucket      = var.access_logs_bucket

  log_level          = "INFO"
  log_retention_days = 30

  readonly_root_filesystem = true
  ecr_keep_images          = 30
  ecr_force_delete         = false

  # Block the apply until the service is stable, so a broken deploy fails the
  # pipeline instead of quietly reporting success.
  wait_for_steady_state = true

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

  error_count_threshold         = 5
  latency_p99_threshold_seconds = 1.5
  ecs_cpu_threshold             = 80
  rds_cpu_threshold             = 75
  rds_free_storage_threshold_gb = 10
  app_error_threshold           = 5

  tags = local.tags
}
