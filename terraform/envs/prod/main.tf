data "aws_caller_identity" "current" {}

locals {
  name  = "${var.project}-${var.environment}"
  image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.project}:${var.image_tag}"
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "security" {
  source = "../../modules/security"

  name           = local.name
  vpc_id         = module.network.vpc_id
  container_port = var.container_port
}

module "database" {
  source = "../../modules/database"

  name              = local.name
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.security.database_security_group_id

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}

module "app" {
  source = "../../modules/app"

  name        = local.name
  environment = var.environment
  region      = var.region

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  app_security_group_id = module.security.app_security_group_id

  image          = local.image
  container_port = var.container_port
  cpu            = var.cpu
  memory         = var.memory
  desired_count  = var.desired_count

  db_host                = module.database.endpoint
  db_port                = module.database.port
  db_name                = module.database.db_name
  db_username            = module.database.username
  db_password_secret_arn = module.database.password_secret_arn

  log_level           = var.log_level
  log_retention_days  = var.log_retention_days
  container_insights  = var.container_insights
  deletion_protection = var.deletion_protection
}

module "monitoring" {
  source = "../../modules/monitoring"

  name   = local.name
  region = var.region

  alb_arn_suffix          = module.app.alb_arn_suffix
  target_group_arn_suffix = module.app.target_group_arn_suffix
  cluster_name            = module.app.cluster_name
  service_name            = module.app.service_name
  db_identifier           = module.database.identifier

  alert_emails    = var.alert_emails
  error_threshold = var.error_threshold
}
