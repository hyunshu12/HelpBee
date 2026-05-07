terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "helpbee-terraform-state"
    key    = "staging/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = "helpbee"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source      = "../../modules/vpc"
  environment = "staging"
  tags        = local.common_tags
}

module "eks" {
  source             = "../../modules/eks"
  environment        = "staging"
  subnet_ids         = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  instance_types     = ["t3.medium"]
  desired_size       = 2
  max_size           = 3
  min_size           = 1
  tags               = local.common_tags
}

module "rds" {
  source              = "../../modules/rds"
  environment         = "staging"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  allowed_cidr_blocks = ["10.0.0.0/16"]
  instance_class      = "db.t3.micro"
  db_username         = var.db_username
  db_password         = var.db_password
  deletion_protection = false
  tags                = local.common_tags
}
