##################################################
#vpc
##################################################

resource "aws_vpc" "testvpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "webapp-vpc"
  }
}

#######################################################
# Internet Gateway
#######################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.testvpc.id
  tags = {
    Name = "webapp-igw"
  }
}


##############################################
# Public Subnets
##############################################
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.testvpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

##################################################
#Private subnets
##################################################
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.testvpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

###################################################
# Public Route Table
###################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.testvpc.id
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

###########################################################
# Associate public subnets with public RT
###########################################################
resource "aws_route_table_association" "public_subnet_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
#######################################################
# NAT Gateways 
#######################################################
resource "aws_eip" "nat" {
  count = length(aws_subnet.public)
}

resource "aws_nat_gateway" "natgw" {
  count         = length(aws_subnet.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = {
    Name = "natgw-${count.index + 1}"
  }
  depends_on = [aws_internet_gateway.igw]
}

##########################################################
# Private Route Tables 
##########################################################
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.testvpc.id
  tags = {
    Name = "private-rt-${count.index + 1}"
  }
}

#########################################################
# NAT Gateway for routing private subnets
#########################################################
resource "aws_route" "private_nat_route" {
  count                  = length(aws_route_table.private)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw[count.index].id
}

########################################################
# Associate private subnets with private Route tables
##########################################################
resource "aws_route_table_association" "private_subnet_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#########################################################
# Security Groups for ALB,Web server, database server
##########################################################
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow inbound HTTP from anywhere"
  vpc_id      = aws_vpc.testvpc.id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP from ALB only, outbound internet & RDS"
  vpc_id      = aws_vpc.testvpc.id

  ingress {
    description      = "HTTP from ALB"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id]
  }

  egress {
    description      = "Allow all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow DB traffic from web tier only"
  vpc_id      = aws_vpc.testvpc.id

  ingress {
    description      = "PostgreSQL from web tier"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.web_sg.id]
  }

  egress {
    description      = "Allow all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}
##############################################################
# IAM Role for EC2 instances (With SSM policy)
##############################################################
resource "aws_iam_role" "ec2_role" {
  name = "webapp-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "webapp-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

#########################################################
# Launch Template for EC2 instances (web tier)
#########################################################
resource "aws_launch_template" "webserver" {
  name_prefix   = "webapp-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_sg.id]
  }
 user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install -y nginx1
    systemctl enable nginx
    systemctl start nginx
    echo "Hello World" > /usr/share/nginx/html/index.html
  EOF
  )



  lifecycle {
    create_before_destroy = true
  }
}

##################################################
# Auto Scaling Group
##################################################
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = var.desired_capacity
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_template {
    id      = aws_launch_template.webserver.id
    version = "$Latest"
  }
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.web_tg.arn]
  tag {
    key                 = "Name"
    value               = "webapp-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
########################################################
# Scaling Policies
########################################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale_out_policy"
  scaling_adjustment      = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale_in_policy"
  scaling_adjustment      = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

#####################################################
# Application Load Balancer 
#####################################################
resource "aws_lb" "web_alb" {
  name               = "webapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "web_tg" {
  name     = "webapp-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.testvpc.id

  health_check {
    enabled             = true
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

##########################################################
# RDS Instance
#########################################################
resource "aws_db_instance" "rds" {
  identifier              = "webapp-rds-instance"
  allocated_storage       = var.rds_allocated_storage
  engine                  = "postgres"
  engine_version          = "16.6"
  instance_class          = var.rds_instance_class
  username                = var.rds_username
  password                = var.rds_password
  multi_az                = true
  publicly_accessible     = false
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "webapp-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = "rds-subnet-group"
  }
}


