data "aws_route53_zone" "selected" {
  count        = var.domain_name == "" ? 0 : 1
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "app" {
  count   = var.domain_name == "" ? 0 : 1
  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
