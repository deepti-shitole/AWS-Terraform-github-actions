resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-vpc" }
  )
}

# Create Public and Private Subnets across AZs
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_list[0]
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-subnet" }
  )
}

resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-south-1a"

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-subnet-az1" }
  )
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-subnet-az2" }
  )
}

# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-igw" }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {}

# NAT Gateway for Private Subnets
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-nat" }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-rt" }
  )
}

# Route for Public Subnet to Internet Gateway
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-rt" }
  )
}

# Route for Private Subnets to NAT Gateway
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Associate Route Tables with Subnets
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private.id
}

# Security Group for SSH
resource "aws_security_group" "ssh" {
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Change to your IP for security
  }

  tags = local.common_tags
}

# EC2 Instances
resource "aws_instance" "public" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = "my-new-key"
  vpc_security_group_ids = [aws_security_group.ssh.id]

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-ec2" }
  )
}

resource "aws_instance" "private" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_az1.id
  key_name               = "my-new-key"
  vpc_security_group_ids = [aws_security_group.ssh.id]

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-ec2" }
  )
}

# Security Group for RDS - Only allows connections from Private EC2
resource "aws_security_group" "rds" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.ssh.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${local.prefix}-db-subnet-group"
  description = "Subnet group for RDS"
  subnet_ids  = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
}

# Generate Random Password for RDS
resource "random_password" "rds_password" {
  length  = 16
  special = false
}

# Store RDS Password in Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {
  name = "${local.prefix}-rds-password"
}

resource "aws_secretsmanager_secret_version" "rds_password_version" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({ password = random_password.rds_password.result })
}

# RDS Instance
resource "aws_db_instance" "postgres" {
  identifier             = "${local.prefix}-postgres"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 30
  storage_type           = "gp2"
  username               = var.db_username
  password               = random_password.rds_password.result
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  skip_final_snapshot    = true
}
