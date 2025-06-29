output "TQO-web1_ip" {
  value = aws_instance.TQO-web1.public_ip
}

output "TQO-web2_ip" {
  value = aws_instance.TQO-web2.public_ip
}

output "TQO-load_balancer_dns" {
  value = aws_lb.TQO-web_lb.dns_name
}
