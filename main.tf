

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-2"
  access_key = "AKIAS552P5PPEAF6IHVL"
  secret_key = "+l6p5C6mX78PNhHeHlLxvYZzKWIChyYNHZ4XKZFH"

}
# resource "aws_instance" "example1" {
#   ami           =  "ami-0fb653ca2d3203ac1" 
#   instance_type = "t2.micro"
#   tags = {
#     Name = "terraform-ejemplo-3"
#   }

# }
# resource "aws_instance" "example" {
#   ami                    = "ami-0fb653ca2d3203ac1"
#   instance_type          = "t2.micro"
#   vpc_security_group_ids = [aws_security_group.instance.id]
#   user_data = <<-EOF
#               #!/bin/bash
#               echo "Hello, World" > index.html
#               nohup busybox httpd -f -p ${var.server_port} &
#               EOF

#   user_data_replace_on_change = true

#   tags = {
#     Name = "terraform-example"
#   }
# }

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  #se puede obviar el default si queremos introducir manualmente el valor
  default = 8080
}
output "alb_dns_name" {
  value       = aws_lb.example.dns_name

description = "The domain name of the load balancer"
}

#Si ese servidor falla o se sobrecarga por exceso de tráfico, los usuarios no podrán acceder al sitio. La solución es ejecutar un clúster de servidores, 
resource "aws_launch_configuration" "example" {
  image_id        = "ami-0fb653ca2d3203ac1"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF  
  # Required when using a launch configuration with an ASG.
  lifecycle {
    create_before_destroy = true
  }
}

#Con la fuente de datos aws_vpc, el único filtro que necesitas es default = true
#Buscara la VPC por defecto y la asignara a la instancia
data "aws_vpc" "default" {

  default = true

}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.asg.arn]
  health_check_type    = "ELB"
  min_size             = 2
  max_size             = 10

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}
# min_size = 2
# max_size = 10
#Puede combinar esto con otra fuente de datos, aws_subnets, para buscar las subredes dentro de esa VPC:
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

//--------------------------- Equilibrador de carga -------------------------------
#ahora tienes múltiples servidores, cada uno con su propia dirección IP, 
#pero normalmente quieres dar a tus usuarios finales sólo una única IP para usar.
# Una forma de resolver este problema es desplegar un equilibrador de carga
resource "aws_lb" "example" {
  name = "terraform-asg-example"

  load_balancer_type = "application"



  #configura el balanceador de carga para que utilice todas las subredes de su VPC predeterminada mediante el origen de datos aws_subnets.
  subnets         = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]

}
#A continuación, debe crear un grupo objetivo para su ASG utilizando el recurso aws_lb_target_group:

resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

#El siguiente paso es definir un listener para este ALB utilizando el recurso aws_lb_listener:
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

#-----------------------Grupo de seguridad para el ALB-----------------------------
#de forma predeterminada, todos los recursos de AWS, incluidos los ALB, no permiten ningún tráfico entrante o saliente, por lo que debe crear un nuevo grupo de seguridad específicamente para el ALB.
resource "aws_security_group" "alb" {
  name = "terraform-example-alb" # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//El código siguiente agrega una regla de escucha que envía solicitudes que coinciden con cualquier ruta al grupo de destino que contiene su ASG.
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}
module "aws_ec2" {
  source = ""
  
}
