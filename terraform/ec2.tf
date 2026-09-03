locals {
  node_names = [
    "jenkins-worker",
    "maven-worker",
    "nexus-worker",
    "web-worker"
  ]
}

resource "aws_instance" "management" {
  for_each = toset(["terraform-server", "ansible-server"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.management.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = each.key }
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.kubernetes.id, aws_security_group.management.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  tags = {
    Name        = "k8s-control-plane"
    Kubernetes  = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public[count.index % 2].id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.kubernetes.id, aws_security_group.management.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name       = local.node_names[count.index]
    Kubernetes = "worker"
    Role       = local.node_names[count.index]
  }
}
