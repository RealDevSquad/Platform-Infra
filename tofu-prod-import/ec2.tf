# EC2 layer: key pair, security group, instance, EIP (import loop).
# Attribute source: live describes via rds-LLM (2026-07-18) + ../docs/aws-layer.md.

resource "aws_key_pair" "deploy" {
  key_name = var.key_pair_name
  # RSA key created 2024-05-20; private key in 1Password ("EC2 RDS Services
  # Single Box - SSH Key"). Comment on the public key equals the key name.
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTaHbh6yL7CwhJM+S52/Zk3P/NzOyIKhnBhuOfQ/N3XcF2zAht0bmShj5q2a+jP+Tg3knDhR95ZLIJsgYpFplT/SHe+Vq70DDa0keitdcCv6D2n9Z9wenYxYXl1YNQzguQEN7SFekjsDfpMlEC4clcurTEKZMgBHGx2AxivUF7UyIgAP643oHnU7X4SiFJ31chjD+lHKuKT+ZouOGyKTDrsQwSypaXEpcj+pL6tXXTvwJpRB/2ytuyleqMSG3jyC6/wf3c31gWFKqY9H4wFe5o73vp7NZfF2wqrdaJ7TaWJyIAh8VSiuV4ftZX8E3iULOWts813GWCf3QzFnpBN8nl ${var.key_pair_name}"

  lifecycle {
    # Unavoidable for imported key pairs: the EC2 read API never returns the
    # public key material into state, and public_key is Required+ForceNew, so
    # without this every plan proposes destroy/recreate. The config value
    # above is still the real public key (docs + greenfield rebuild).
    ignore_changes = [public_key]
  }
}

resource "aws_instance" "services" {
  # Ubuntu 22.04 arm64 (public Canonical AMI), launched 2024-05-20.
  ami           = "ami-072b1c33a2439c226"
  instance_type = "t4g.medium"

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.main.id]
  key_name               = aws_key_pair.deploy.key_name
  iam_instance_profile   = aws_iam_instance_profile.backup.name

  ebs_optimized     = true
  monitoring        = false
  source_dest_check = true

  credit_specification {
    cpu_credits = "unlimited"
  }

  # IMDSv2 enforced; hop limit 2 so containers on the docker bridge can still
  # reach the instance-profile credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "disabled"
  }

  # Root volume (30G gp2) and the 5 data volumes are modeled as standalone
  # aws_ebs_volume + aws_volume_attachment resources in ebs.tf — no
  # root_block_device / ebs_block_device blocks here on purpose.

  tags = {
    Name = "RDS services server"
  }
}

resource "aws_security_group" "main" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2024-05-20T13:28:32.329Z"
  vpc_id      = var.vpc_id

  # Inbound: ssh + http + https from anywhere. App ports 3010-4050 are
  # host-published but deliberately NOT opened here (see docs/aws-layer.md).
  ingress {
    description      = ""
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }

  ingress {
    description      = ""
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }

  ingress {
    description      = ""
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }

  egress {
    description      = ""
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }
}

resource "aws_eip" "services" {
  domain = "vpc"

  tags = {
    Name = "RDS-service-server-ip"
    # Real tag on the EIP: key equals the key-pair name, empty value.
    (var.key_pair_name) = ""
  }
}

resource "aws_eip_association" "services" {
  allocation_id = aws_eip.services.id
  instance_id   = aws_instance.services.id
}
