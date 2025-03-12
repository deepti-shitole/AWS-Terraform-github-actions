resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-vpc" }
  )
}

#5. Create Subnets
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_list[0]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-subnet" }
  )
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_list[1]

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-subnet" }
  )
}

# Private Subnet in AZ1
resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
}

# Private Subnet in AZ2
resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"
}



#6. Set Up Internet Gateway and attach to vpc  
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-igw" }
  )
}

#7. create a EIP 
#EIP which will be used by Nat gateway.
resource "aws_eip" "public" {
     tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public" }
  )
}


#8. create a Nat gateway using the EIP created in last step
resource "aws_nat_gateway" "public" {
  allocation_id = aws_eip.public.id
  subnet_id     = aws_subnet.public.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-a" }
  )
}

#7. Create 2 Route Tables , one for each subnet (public, private)

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public" }
  )
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private" }
  )
}

#8.create 2 route. one for public subnet and another for private subnet. the private route will use the nat gateway and public route will the internet gateway as gateway_id 
 resource "aws_route" "private-internet_out"{
 route_table_id = aws_route_table.private.id
nat_gateway_id = aws_nat_gateway.public.id
destination_cidr_block = "0.0.0.0/0"   
 }                              #Routes all outbound traffic (0.0.0.0/0) to the nat Gateway, 

 resource "aws_route" "public_internet_access"{
 route_table_id = aws_route_table.public.id
destination_cidr_block = "0.0.0.0/0"                                       #Routes all inbound traffic (0.0.0.0/0) through the Internet Gateway
gateway_id = aws_internet_gateway.main.id
 }


#9.created the routes associated with public and private subnet

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#10.create a security group that allows ssh connection to both the ec2 instances.

resource "aws_security_group" "ssh" {
  description = "allow ssh to ec2"
  name = "${local.prefix}-ssh_access"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
     tags = local.common_tags
}


#11. Create 2 EC2 Instances, one in public & other in private subnet.
# private ec2 instance
resource "aws_instance" "private" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private.id
  availability_zone = "${data.aws_region.current.name}b"
  vpc_security_group_ids = [ aws_security_group.ssh.id,]
  key_name = "my-new-key"
  
 tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-private-ec2" }
  )
}

# public ec2 instance
resource "aws_instance" "public" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  availability_zone = "${data.aws_region.current.name}a"
  vpc_security_group_ids = [ aws_security_group.ssh.id,]
  key_name = "my-new-key"

  tags = merge(
    local.common_tags,
    { "Name" = "${local.prefix}-public-ec2" }
  )
}


#12. Create an RDS instance
resource "aws_db_instance" "postgres" {
  identifier             = "${var.db_name}-postgres"
  engine                 = "postgres"
  engine_version         = "15"  
  instance_class         = "db.t3.micro"  
  allocated_storage      = 30 
  storage_type           = "gp2"
  username               = var.db_username
  password               = random_password.rds_password.result
  vpc_security_group_ids = [aws_security_group.rds.id]  # Assign security group
  db_subnet_group_name   = aws_db_subnet_group.main.name
  skip_final_snapshot = true
}
# Generate a Random Password for RDS
resource "random_password" "rds_password" {
  length           = 16
  special          = false
}

# Store RDS  Password  in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {  
  name = "${var.prefix}-rds-password"
}



resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    password = random_password.rds_password.result
    })
}


#13.create a security group for rds that will allow ingress on the DB port from a private instance. Also created a subnet group.
# RDS Security Group - Allows inbound traffic only from the Application Layer
resource "aws_security_group" "rds" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private_az1.cidr_block, aws_subnet.private_az2.cidr_block] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# RDS Subnet Group - Required for Multi-AZ and Private Subnet Deployment
# RDS Subnet Group - Required for Multi-AZ Deployment
resource "aws_db_subnet_group" "main" {
  name        = "${var.prefix}-db-subnet-group"
  description = "Subnet group for RDS in private subnets"
  
  # Include at least two subnets from different Availability Zones
  subnet_ids  = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]  
}
