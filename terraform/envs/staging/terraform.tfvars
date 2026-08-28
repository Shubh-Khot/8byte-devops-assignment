# Staging values. Non-sensitive on purpose - this file is committed.
# Secrets come from Secrets Manager or TF_VAR_ environment variables.

project     = "taskapi"
environment = "staging"
region      = "ap-south-1"

vpc_cidr = "10.20.0.0/16"

db_instance_class = "db.t3.micro"

# Replace with a real address before applying, then confirm the SNS
# subscription email - it stays pending until someone clicks the link.
alert_emails = []

# alb_ingress_cidrs = ["203.0.113.0/24"]   # narrow this once you have a fixed egress IP

# Set these only if the account blocks ec2:DescribeAvailabilityZones.
# availability_zones = ["ap-south-1a", "ap-south-1b"]
