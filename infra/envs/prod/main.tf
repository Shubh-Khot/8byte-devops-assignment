data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  container_image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_name}:${var.image_tag}"
}

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}

module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  app_port    = var.app_port
}

module "database" {
  source = "../../modules/database"

  name_prefix           = local.name_prefix
  private_subnet_ids    = module.network.private_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id

  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
}

module "app" {
  source = "../../modules/app"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  ecs_security_group_id = module.security.ecs_security_group_id

  container_image   = local.container_image
  container_name    = var.project
  app_port          = var.app_port
  health_check_path = var.health_check_path
  cpu               = var.cpu
  memory            = var.memory
  desired_count     = var.desired_count

  db_endpoint   = module.database.db_endpoint
  db_port       = module.database.db_port
  db_name       = module.database.db_name
  db_username   = var.db_username
  db_secret_arn = module.database.db_secret_arn
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  ecs_cluster_name        = module.app.ecs_cluster_name
  ecs_service_name        = module.app.ecs_service_name
  alb_arn_suffix          = module.app.alb_arn_suffix
  target_group_arn_suffix = module.app.target_group_arn_suffix
  db_instance_id          = module.database.db_instance_id

  alert_emails = var.alert_emails
}
