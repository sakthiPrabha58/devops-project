resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 30080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/api/health"
    port                = "30080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval             = 30
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "workers" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.worker[count.index].id
  port             = 30080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
