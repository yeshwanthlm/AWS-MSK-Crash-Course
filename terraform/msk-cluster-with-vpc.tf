terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "msk_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "MSK-VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "msk_igw" {
  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "MSK-VPC-IGW"
  }
}

# Subnets
resource "aws_subnet" "msk_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "MSK-Subnet-${count.index + 1}"
  }
}

# Route Table
resource "aws_route_table" "msk_rt" {
  vpc_id = aws_vpc.msk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.msk_igw.id
  }

  tags = {
    Name = "MSK-VPC-RT"
  }
}

# Route Table Associations
resource "aws_route_table_association" "msk_rta" {
  count          = 3
  subnet_id      = aws_subnet.msk_subnets[count.index].id
  route_table_id = aws_route_table.msk_rt.id
}

# Security Group for MSK
resource "aws_security_group" "msk_sg" {
  name_prefix = "msk-cluster-sg"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MSK-Security-Group"
  }
}

# MSK Cluster
resource "aws_msk_cluster" "my_demo_msk_cluster" {
  cluster_name           = "my-demo-msk-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = aws_subnet.msk_subnets[*].id
    security_groups = [aws_security_group.msk_sg.id]
    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.msk_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.msk_subnets[*].id
}

output "msk_cluster_arn" {
  value = aws_msk_cluster.my_demo_msk_cluster.arn
}

output "bootstrap_brokers" {
  value = aws_msk_cluster.my_demo_msk_cluster.bootstrap_brokers_tls
}
