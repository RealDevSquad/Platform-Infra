variable "aws_region" {
  type        = string
  description = "Region for the sandbox box."
  default     = "ap-south-1"
}

variable "env_name" {
  type        = string
  description = "Short name for this sandbox (used in resource names + the SSM path /rds/<env_name>/)."
  default     = "sandbox"
}

variable "subdomain" {
  type        = string
  description = "The subdomain you own that will point at this box (e.g. sandbox.yourdomain.com). Used only in outputs to tell you the DNS record to create + the SITE_ADDRESS to set."
}

variable "instance_type" {
  type        = string
  description = "arm64 (Graviton) instance type. t4g.medium = 2 vCPU / 4 GB, same as legacy."
  default     = "t4g.medium"
}

variable "root_gb" {
  type    = number
  default = 30
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to SSH (port 22), e.g. 203.0.113.4/32. Empty (default) = port 22 is not opened at all; Session Manager is the shell."
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Optional SSH public key. Leave empty to use SSM Session Manager only (no key, keyless shell)."
  default     = ""
}
