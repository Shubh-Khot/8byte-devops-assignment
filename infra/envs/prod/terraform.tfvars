environment = "prod"
vpc_cidr    = "10.30.0.0/16"

db_instance_class          = "db.t3.small"
db_multi_az                = true
db_backup_retention_period = 14
db_skip_final_snapshot     = false

desired_count       = 2
deletion_protection = true

alert_emails = []
