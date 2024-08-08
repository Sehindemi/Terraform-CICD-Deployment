data "aws_ami" "ec2_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "cicd_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.project_name
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.cicd_vpc.id
  cidr_block              = var.public_cidr[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${var.project_name}-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "public-igw" {
  vpc_id = aws_vpc.cicd_vpc.id
}

resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.cicd_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public-igw.id
  }
}
resource "aws_route_table_association" "public-rt-assoc" {
  count          = var.public_subnet_count
  subnet_id      = aws_subnet.public_subnet.*.id[count.index]
  route_table_id = aws_route_table.public-route.id
}

resource "aws_security_group" "public_vpc_sg" {
  name   = "cicd-sg"
  vpc_id = aws_vpc.cicd_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.access_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ssh"
  }
}

resource "aws_instance" "public_ec2" {
  for_each               = toset(["Jenkins-Master", "Build-Slave", "Ansible"])
  instance_type          = "t2.micro"
  key_name               = "cicd-infra"
  ami                    = data.aws_ami.ec2_ami.id
  vpc_security_group_ids = [aws_security_group.public_vpc_sg.id]
  subnet_id = aws_subnet.public_subnet[0].id
  tags = {
    Name = "${each.key}-cicd-infra"
  }
}
