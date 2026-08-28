# Production values. Committed; contains nothing secret.

project     = "taskapi"
environment = "prod"
region      = "ap-south-1"

vpc_cidr = "10.30.0.0/16"

db_instance_class = "db.t4g.small"

# Graviton (t4g) is ~10% cheaper than t3 for the same class and performs
# better on Postgres. The only reason staging is not on it is that free tier
# covers db.t3.micro.

alert_emails = []

# certificate_arn    = "arn:aws:acm:ap-south-1:<account>:certificate/<id>"
# access_logs_bucket = "taskapi-prod-alb-logs"
