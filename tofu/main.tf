# The box module — CREATES a fresh services box from scratch in any account.
# First consumer: the sandbox dev account; later: the prod successor.
# The opposite of ../tofu-prod-import/, which IMPORTS the hand-built box.
# Run with the target account's admin creds — it is entirely yours.
#
#   cd tofu
#   cp terraform.tfvars.example terraform.tfvars   # fill subdomain + region
#   tofu init && tofu plan && tofu apply
#
# State is local (terraform.tfstate) and holds your account's IDs — never commit.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
  # Uses your normal credential chain (SSO/env/profile). No profile pinned here
  # on purpose — this is your account, you choose how you authenticate.
  default_tags {
    tags = { Project = "rds-infra-sandbox", ManagedBy = "opentofu", Env = var.env_name }
  }
}

# --- Network: use the account's default VPC/subnet (simplest for one public box) ---
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Latest Ubuntu 24.04 arm64 AMI, resolved automatically (no hardcoded AMI) ---
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

# --- Security group: 80/443 public, 22 only from your admin CIDR ---
resource "aws_security_group" "box" {
  name        = "rds-${var.env_name}-box"
  description = "RDS sandbox services box"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (ACME + redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP/3"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH is opt-in: no admin_cidr set -> port 22 is not opened at all (SSM-only).
  dynamic "ingress" {
    for_each = var.admin_cidr == "" ? [] : [var.admin_cidr]
    content {
      description = "SSH (admin only)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM: instance role. SSM core = keyless Session Manager shell (the "right
# way" the legacy box never had). Plus scoped S3 backup write + SSM param read. ---
resource "aws_iam_role" "box" {
  name = "rds-${var.env_name}-box"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole", Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.box.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "box" {
  name = "backups-and-params"
  role = aws_iam_role.box.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BackupWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
      },
      {
        Sid      = "ParamRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParametersByPath", "ssm:GetParameters", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/rds/${var.env_name}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "box" {
  name = "rds-${var.env_name}-box"
  role = aws_iam_role.box.name
}

# --- Optional SSH key (Session Manager works without it) ---
resource "aws_key_pair" "box" {
  count      = var.ssh_public_key == "" ? 0 : 1
  key_name   = "rds-${var.env_name}-box"
  public_key = var.ssh_public_key
}

# --- The box ---
resource "aws_instance" "box" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.box.id]
  iam_instance_profile   = aws_iam_instance_profile.box.name
  key_name               = var.ssh_public_key == "" ? null : aws_key_pair.box[0].key_name

  root_block_device {
    volume_size = var.root_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "rds-${var.env_name}-box" }
}

resource "aws_eip" "box" {
  domain   = "vpc"
  instance = aws_instance.box.id
  tags     = { Name = "rds-${var.env_name}-box-ip" }
}

# --- Backup bucket (name auto-unique via prefix) ---
resource "aws_s3_bucket" "backups" {
  bucket_prefix = "rds-${var.env_name}-backups-"
  force_destroy = true # sandbox: allow teardown even if non-empty
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
