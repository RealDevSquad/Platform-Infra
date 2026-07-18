output "public_ip" {
  value       = aws_eip.box.public_ip
  description = "Elastic IP of the sandbox box."
}

output "instance_id" {
  value = aws_instance.box.id
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "dns_record_to_create" {
  value       = "A  ${var.subdomain}  ->  ${aws_eip.box.public_ip}  (grey-cloud / DNS-only so Caddy ACME can validate)"
  description = "Create this record in your DNS provider, then Caddy gets a real cert on first request."
}

output "site_address_env" {
  value       = "SITE_ADDRESS=${var.subdomain}"
  description = "Put this line in docker/.env on the box (with COMPOSE_FILE=compose.yaml:compose.prod.yaml)."
}

output "ssm_session" {
  value       = "aws ssm start-session --target ${aws_instance.box.id} --region ${var.aws_region}"
  description = "Keyless shell into the box (no SSH key needed)."
}

output "next_steps" {
  value = <<-EOT
    1. Create the DNS record above (subdomain -> public_ip).
    2. Get the repo onto the box:  scp -r <repo> ubuntu@${aws_eip.box.public_ip}:~/Infra
       (or via Session Manager). Then on the box:
    3. cd ~/Infra && ./scripts/bootstrap.sh
       - fill docker/env/*.env (manual provider) with your staging-tier values
       - set docker/.env:  DOCKERHUB_USER=...  COMPOSE_FILE=compose.yaml:compose.prod.yaml  SITE_ADDRESS=${var.subdomain}  COMPOSE_PROFILES=todo,skilltree,tinysite,discord
    4. Verify:  ./scripts/validate-stack.sh   and  curl https://${var.subdomain}/todo/api/schema
  EOT
}
