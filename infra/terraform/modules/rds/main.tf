resource "aws_db_subnet_group" "this" {
  name       = "${var.environment}-${var.project_name}-rds-subnet"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "rds" {
  name   = "${var.environment}-${var.project_name}-rds-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier = "${var.environment}-${var.project_name}-rds"

  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = !var.deletion_protection

  tags = var.tags
}
