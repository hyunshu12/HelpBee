variable "environment" {
  type = string
}

variable "project_name" {
  type    = string
  default = "helpbee"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "subnet_ids" {
  description = "Subnets for EKS control plane"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for node groups"
  type        = list(string)
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "min_size" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
