resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "TQO-subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "TQO-subnet2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_internet_gateway" "TQO-igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "TQO-rt" {
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "TQO-web_sg" {
  name   = "TQO-web-sg"
  vpc_id = aws_vpc.main.id

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

resource "aws_instance" "TQO-web1" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.TQO-subnet1.id
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.TQO-web_sg.id]
  user_data     = file("install_web.sh")

  tags = {
    Name = "TQO-WebServer1"
  }
}

resource "aws_instance" "TQO-web2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.TQO-subnet2.id
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.TQO-web_sg.id]
  user_data     = file("install_web.sh")

  tags = {
    Name = "TQO-WebServer2"
  }
}

resource "aws_lb" "TQO-web_lb" {
  name               = "TQO-web-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.TQO-subnet1.id, aws_subnet.TQO-subnet2.id]
  security_groups    = [aws_security_group.TQO-web_sg.id]
}

resource "aws_lb_target_group" "TQO-web_tg" {
  name     = "TQO-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "TQO-web1_attach" {
  target_group_arn = aws_lb_target_group.TQO-web_tg.arn
  target_id        = aws_instance.TQO-web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "TQO-web2_attach" {
  target_group_arn = aws_lb_target_group.TQO-web_tg.arn
  target_id        = aws_instance.TQO-web2.id
  port             = 80
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
