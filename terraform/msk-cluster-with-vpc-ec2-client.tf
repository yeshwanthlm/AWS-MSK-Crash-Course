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

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
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

# Key Pair
resource "aws_key_pair" "msk_client_key" {
  key_name   = "msk-client-key"
  public_key = tls_private_key.msk_client_key.public_key_openssh
}

resource "tls_private_key" "msk_client_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content         = tls_private_key.msk_client_key.private_key_pem
  filename        = "${path.module}/msk-client-key.pem"
  file_permission = "0400"
}

# Security Group for MSK
resource "aws_security_group" "msk_sg" {
  name_prefix = "msk-cluster-sg"
  vpc_id      = aws_vpc.msk_vpc.id

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

# Security Group for EC2
resource "aws_security_group" "ec2_sg" {
  name_prefix = "msk-client-sg"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MSK-Client-Security-Group"
  }
}

# Security Group Rules
resource "aws_security_group_rule" "msk_from_ec2" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.ec2_sg.id
  security_group_id        = aws_security_group.msk_sg.id
}

resource "aws_security_group_rule" "ec2_from_msk" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.msk_sg.id
  security_group_id        = aws_security_group.ec2_sg.id
}

# IAM Role for EC2
resource "aws_iam_role" "msk_client_role" {
  name = "MSK-Client-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "msk_client_policy" {
  name = "MSK-Client-Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk_client_policy_attachment" {
  role       = aws_iam_role.msk_client_role.name
  policy_arn = aws_iam_policy.msk_client_policy.arn
}

resource "aws_iam_instance_profile" "msk_client_profile" {
  name = "MSK-Client-Profile"
  role = aws_iam_role.msk_client_role.name
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

# EC2 Instance
resource "aws_instance" "msk_client" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.msk_client_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.msk_subnets[0].id
  iam_instance_profile   = aws_iam_instance_profile.msk_client_profile.name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum -y install java-11
    cd /home/ec2-user
    wget https://archive.apache.org/dist/kafka/3.6.0/kafka_2.13-3.6.0.tgz
    tar -xzf kafka_2.13-3.6.0.tgz
    cd kafka_2.13-3.6.0/libs
    wget https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.1/aws-msk-iam-auth-1.1.1-all.jar
    cd /home/ec2-user/kafka_2.13-3.6.0/bin/
    cat << 'EOL' > client.properties
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOL
    chown -R ec2-user:ec2-user /home/ec2-user/kafka_2.13-3.6.0
  EOF

  tags = {
    Name = "MSK-Client-EC2"
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
  value = aws_msk_cluster.my_demo_msk_cluster.bootstrap_brokers_sasl_iam
}

output "ec2_instance_id" {
  value = aws_instance.msk_client.id
}

output "ec2_public_ip" {
  value = aws_instance.msk_client.public_ip
}

output "private_key_path" {
  value = local_file.private_key.filename
}
