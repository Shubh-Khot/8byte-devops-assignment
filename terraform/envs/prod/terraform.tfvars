environment = "prod"
vpc_cidr    = "10.30.0.0/16"

db_instance_class        = "db.t4g.small"
db_multi_az              = true
db_backup_retention_days = 14
db_skip_final_snapshot   = false

desired_count       = 2
deletion_protection = true
container_insights  = true
log_retention_days  = 30

alert_emails = []
