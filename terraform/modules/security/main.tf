resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public entry point. Accepts HTTP from the internet."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "ECS tasks. Only the load balancer may reach them."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Application port from the load balancer"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-app" }
}

resource "aws_security_group" "database" {
  name        = "${var.name}-db"
  description = "RDS. Only the ECS tasks may reach it."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from the application"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.name}-db" }
}
