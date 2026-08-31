environment = "staging"
vpc_cidr    = "10.20.0.0/16"

db_instance_class = "db.t3.micro"
desired_count     = 1

log_retention_days = 7

# Subscribe an address here to actually receive alarm notifications; the SNS
# topic and the five alarms exist either way.
alert_emails = []
