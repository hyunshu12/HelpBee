variable "environment" { type = string }
variable "project_name" { type = string; default = "helpbee" }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_cidr_blocks" { type = list(string) }
variable "postgres_version" { type = string; default = "16.2" }
variable "instance_class" { type = string; default = "db.t3.micro" }
variable "db_name" { type = string; default = "helpbee" }
variable "db_username" { type = string }
variable "db_password" { type = string; sensitive = true }
variable "allocated_storage" { type = number; default = 20 }
variable "max_allocated_storage" { type = number; default = 100 }
variable "backup_retention_period" { type = number; default = 7 }
variable "deletion_protection" { type = bool; default = true }
variable "tags" { type = map(string); default = {} }
