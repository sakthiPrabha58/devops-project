output "terraform_server_ip" {
  value = aws_instance.management["terraform-server"].public_ip
}

output "ansible_server_ip" {
  value = aws_instance.management["ansible-server"].public_ip
}

output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "worker_ips" {
  value = {
    for i, instance in aws_instance.worker : local.node_names[i] => instance.public_ip
  }
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}

output "s3_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "application_url" {
  value = var.domain_name == "" ? "http://${aws_lb.app.dns_name}" : "http://app.${var.domain_name}"
}
