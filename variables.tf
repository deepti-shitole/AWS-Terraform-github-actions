variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "prefix" {
  default = "main"
}

variable "project" {
  default = "devops-102"
}

variable "contact" {
  default = "deeptishitole@gmail.com"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr_list" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "mydatabase"  # Change this as needed
}

variable "db_username" {
  description = "Username for the PostgreSQL database"
  type        = string
  default     = "admin"  # Change this as needed
}
