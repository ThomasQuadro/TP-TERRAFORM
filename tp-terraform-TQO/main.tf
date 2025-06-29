# ───────────────────────────────────────────────
# VPC
# ───────────────────────────────────────────────
resource "aws_vpc" "TQO-main" {
  cidr_block = "10.0.0.0/16"
}

# ───────────────────────────────────────────────
# Subnets
# ───────────────────────────────────────────────
resource "aws_subnet" "TQO-subnet1" {
  vpc_id                  = aws_vpc.TQO-main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "TQO-subnet2" {
  vpc_id                  = aws_vpc.TQO-main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# ───────────────────────────────────────────────
# Internet Gateway
# ───────────────────────────────────────────────
resource "aws_internet_gateway" "TQO-igw" {
  vpc_id = aws_vpc.TQO-main.id
}

# ───────────────────────────────────────────────
# Route Table & Associations
# ───────────────────────────────────────────────
resource "aws_route_table" "TQO-rt" {
  vpc_id = aws_vpc.TQO-main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.TQO-igw.id
  }
}

resource "aws_route_table_association" "TQO-a1" {
  subnet_id      = aws_subnet.TQO-subnet1.id
  route_table_id = aws_route_table.TQO-rt.id
}

resource "aws_route_table_association" "TQO-a2" {
  subnet_id      = aws_subnet.TQO-subnet2.id
  route_table_id = aws_route_table.TQO-rt.id
}

# ───────────────────────────────────────────────
# Security Group
# ───────────────────────────────────────────────
resource "aws_security_group" "TQO-web_sg" {
  name   = "TQO-web-sg"
  vpc_id = aws_vpc.TQO-main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ───────────────────────────────────────────────
# Load Balancer
# ───────────────────────────────────────────────
resource "aws_lb" "TQO-web_lb" {
  name               = "TQO-web-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [
    aws_subnet.TQO-subnet1.id,
    aws_subnet.TQO-subnet2.id
  ]
  security_groups = [aws_security_group.TQO-web_sg.id]
}

# ───────────────────────────────────────────────
# Target Group & Listener
# ───────────────────────────────────────────────
resource "aws_lb_target_group" "TQO-web_tg" {
  name     = "TQO-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.TQO-main.id
}

resource "aws_lb_listener" "TQO-web_listener" {
  load_balancer_arn = aws_lb.TQO-web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TQO-web_tg.arn
  }
}

# ───────────────────────────────────────────────
# Launch Template avec user_data (avec sudo)
# ───────────────────────────────────────────────
resource "aws_launch_template" "TQO-lt" {
  name_prefix   = "TQO-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.TQO-web_sg.id]

  user_data = base64encode(file("install_web.sh"))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "TQO-ASG-Instance"
    }
  }
}

# ───────────────────────────────────────────────
# Auto Scaling Group
# ───────────────────────────────────────────────
resource "aws_autoscaling_group" "TQO-asg" {
  name                = "TQO-asg"
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [
    aws_subnet.TQO-subnet1.id,
    aws_subnet.TQO-subnet2.id
  ]

  launch_template {
    id      = aws_launch_template.TQO-lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.TQO-web_tg.arn]

  tag {
    key                 = "Name"
    value               = "TQO-ASG-Instance"
    propagate_at_launch = true
  }
}
