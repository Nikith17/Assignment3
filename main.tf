provider "aws" {
  region = "us-east-1"
}

# VPC Setup
resource "aws_vpc" "donthi_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Public Subnet
resource "aws_subnet" "donthi_public_subnet" {
  vpc_id                  = aws_vpc.donthi_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "DonthiPublicSubnet"
  }
}

# Private Subnet
resource "aws_subnet" "donthi_private_subnet" {
  vpc_id                  = aws_vpc.donthi_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  tags = {
    Name = "DonthiPrivateSubnet"
  }
}

# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "donthi_igw" {
  vpc_id = aws_vpc.donthi_vpc.id
}

# Security Group for ECS tasks
resource "aws_security_group" "donthi_ecs_sg" {
  vpc_id = aws_vpc.donthi_vpc.id

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

  tags = {
    Name = "DonthiECS_SG"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# ECS Cluster
resource "aws_ecs_cluster" "donthi_ecs_cluster" {
  name = "DonthiECSCluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "donthi_task_definition" {
  family                   = "DonthiTaskDefinition"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([{
    name         = "DonthiAppContainer"
    image        = "897729119415.dkr.ecr.us-east-1.amazonaws.com/donthiapp:latest"
    essential    = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
    memory        = 512
    memoryReservation = 256
  }])
}

# Application Load Balancer (ALB)
resource "aws_lb" "donthi_alb" {
  name               = "DonthiALB"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.donthi_ecs_sg.id]
  subnets           = [aws_subnet.donthi_public_subnet.id]
  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "DonthiALB"
  }
}

# ALB Listener
resource "aws_lb_listener" "donthi_alb_listener" {
  load_balancer_arn = aws_lb.donthi_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "Hello from Donthi ECS Container!"
    }
  }
}

# ECS Service
resource "aws_ecs_service" "donthi_ecs_service" {
  name            = "DonthiService"
  cluster         = aws_ecs_cluster.donthi_ecs_cluster.id
  task_definition = aws_ecs_task_definition.donthi_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.donthi_private_subnet.id]
    security_groups = [aws_security_group.donthi_ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.donthi_target_group.arn
    container_name   = "DonthiAppContainer"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.donthi_alb_listener
  ]
}

# Target Group for ALB
resource "aws_lb_target_group" "donthi_target_group" {
  name     = "DonthiTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.donthi_vpc.id
}

# Auto Scaling Configuration for ECS Service
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.donthi_ecs_cluster.name}/DonthiService"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_scaling_policy" {
  name               = "DonthiScalingPolicy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
