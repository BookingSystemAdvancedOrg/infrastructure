# The gateway's wss endpoint for the dev A2A test: ECS Fargate ARM64 behind an internet-facing ALB
# (App Runner has no WebSockets), TLS on the ALB with an ACM certificate for voice-a2a.<platform
# domain>, in the default VPC with a public IP on the task (dev has no NAT). About $0.095 per hour
# while it exists (CONNECT-A2A dev test plan); gateway_count = 0 stops Fargate only.
#
# The image: application CI builds services/voice-gateway/Dockerfile and pushes it to this module's
# ECR repository (tag var.image_tag). Until then the tasks cannot start (the circuit breaker stops
# the deployment) and Connect falls back to the Stage 1 flow.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# --- image and logs ----------------------------------------------------------------------

# The repository lives in eu-north-1 (provider aws.ecr, the root's default region): application CI's
# deploy role may only push to eu-north-1 repositories. Fargate in eu-central-1 pulls from it.
# New resource name on purpose: the old eu-central-1 repository (same name) was in state under "gateway", so a
# plain provider change refreshed against the wrong region.
resource "aws_ecr_repository" "gateway_eu_north_1" {
  provider             = aws.ecr
  name                 = local.name
  image_tag_mutability = "MUTABLE"
  # Dev test: the repository goes with the flag, images included.
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = { Environment = var.environment }
}

resource "aws_ecr_lifecycle_policy" "gateway_eu_north_1" {
  provider   = aws.ecr
  repository = aws_ecr_repository.gateway_eu_north_1.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
  tags              = { Environment = var.environment }
}

# The gateway's tuning JSON (VG_CONFIG_JSON); "{}" = the code defaults. Edited by hand in a test
# session, so Terraform keeps whatever value it has.
resource "aws_ssm_parameter" "config" {
  name        = "/booqy/${var.environment}/voice-gateway/config"
  description = "Voice gateway tuning JSON (VG_CONFIG_JSON); {} = defaults"
  type        = "String"
  value       = "{}"
  tags        = { Environment = var.environment }

  lifecycle {
    ignore_changes = [value]
  }
}

# --- roles (4. in connect-ai.tf's IAM call-out) ------------------------------------------

resource "aws_iam_role" "execution" {
  name = "${local.name}-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
  tags = { Environment = var.environment }
}

# ECS pulls the image, writes the logs and injects the API key and the config.
resource "aws_iam_role_policy" "execution" {
  name = "execution"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrLogin", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Sid      = "PullImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = aws_ecr_repository.gateway_eu_north_1.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.gateway.arn}:*"
      },
      { Sid = "ApiKey", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.a2a.arn },
      { Sid = "ApiKeyDecrypt", Effect = "Allow", Action = ["kms:Decrypt"], Resource = aws_kms_key.a2a.arn },
      { Sid = "Config", Effect = "Allow", Action = ["ssm:GetParameters"], Resource = aws_ssm_parameter.config.arn },
    ]
  })
}

resource "aws_iam_role" "task" {
  name = "${local.name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
  tags = { Environment = var.environment }
}

# What the gateway calls: Transcribe streaming and Polly in eu-central-1 (neither has resource-level
# permissions), plus the phone agent's own access as on phone-agent-call (its table, events, the
# platform row, the tool and notification Lambdas' live aliases, the owners index, the Bedrock model),
# without phone-agent-call's provider and endpoint secrets. The adapter needs no AWS permission
# (Connect calls the gateway; ECS injects the key).
resource "aws_iam_role_policy" "task" {
  name = "gateway"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "Listen"
        Effect    = "Allow"
        Action    = ["transcribe:StartStreamTranscription", "transcribe:StartStreamTranscriptionWebSocket"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        Sid       = "Speak"
        Effect    = "Allow"
        Action    = ["polly:SynthesizeSpeech"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
    ], var.gateway_statements)
  })
}

# Tenant and location reads (shared/tenant.py), as on every tenant-aware Lambda role.
resource "aws_iam_role_policy_attachment" "task_tenant_context" {
  role       = aws_iam_role.task.name
  policy_arn = var.tenant_context_policy_arn
}

# --- task and service --------------------------------------------------------------------

resource "aws_ecs_cluster" "gateway" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  tags = { Environment = var.environment }
}

resource "aws_ecs_task_definition" "gateway" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  container_definitions = jsonencode([{
    name      = "gateway"
    image     = "${aws_ecr_repository.gateway_eu_north_1.repository_url}:${var.image_tag}"
    essential = true
    command   = ["python", "-m", "voice_gateway.server", "connect", "--port", "8443", "--health-port", "8080"]
    portMappings = [
      { containerPort = 8443, protocol = "tcp" },
    ]
    # The server drains running calls for 110 s on SIGTERM.
    stopTimeout = 120
    environment = [for k, v in merge(var.gateway_environment, {
      # The agent's tables, tools and model live there; Transcribe and Polly are pinned to
      # eu-central-1 in the gateway's own config.
      AWS_REGION         = var.agent_region
      AWS_DEFAULT_REGION = var.agent_region
      VG_APP_ROOT        = "/app"
    }) : { name = k, value = v }]
    secrets = [
      { name = "VG_A2A_API_KEY", valueFrom = aws_secretsmanager_secret.a2a.arn },
      { name = "VG_CONFIG_JSON", valueFrom = aws_ssm_parameter.config.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.gateway.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "gateway"
      }
    }
  }])
  tags = { Environment = var.environment }
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Voice gateway A2A ALB: wss from Connect (no published source ranges)"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Environment = var.environment }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "wss from Amazon Connect"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_task" {
  security_group_id            = aws_security_group.alb.id
  description                  = "to the gateway tasks"
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
  referenced_security_group_id = aws_security_group.task.id
}

resource "aws_security_group" "task" {
  name        = "${local.name}-task"
  description = "Voice gateway A2A tasks: 8443 from the ALB only"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Environment = var.environment }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  description                  = "ws and /health from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
  referenced_security_group_id = aws_security_group.alb.id
}

# AWS APIs (Transcribe, Polly, Bedrock, DynamoDB, Lambda, ECR) over the task's public IP.
resource "aws_vpc_security_group_egress_rule" "task_https" {
  security_group_id = aws_security_group.task.id
  description       = "AWS APIs over HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_lb" "gateway" {
  name                       = local.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = data.aws_subnets.default.ids
  idle_timeout               = 300
  drop_invalid_header_fields = true
  tags                       = { Environment = var.environment }
}

resource "aws_lb_target_group" "gateway" {
  name                 = "${local.prefix}vg-a2a"
  port                 = 8443
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.default.id
  deregistration_delay = 120
  health_check {
    path                = "/health"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = { Environment = var.environment }
}

resource "aws_acm_certificate" "gateway" {
  domain_name       = local.hostname
  validation_method = "DNS"
  tags              = { Environment = var.environment }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.gateway.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }
  zone_id         = var.platform_domain_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "gateway" {
  certificate_arn         = aws_acm_certificate.gateway.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gateway.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.gateway.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

resource "aws_route53_record" "gateway" {
  zone_id = var.platform_domain_zone_id
  name    = local.hostname
  type    = "A"
  alias {
    name                   = aws_lb.gateway.dns_name
    zone_id                = aws_lb.gateway.zone_id
    evaluate_target_health = false
  }
}

resource "aws_ecs_service" "gateway" {
  name                              = local.name
  cluster                           = aws_ecs_cluster.gateway.id
  task_definition                   = aws_ecs_task_definition.gateway.arn
  desired_count                     = var.gateway_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60
  propagate_tags                    = "SERVICE"
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "gateway"
    container_port   = 8443
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }
  tags       = { Environment = var.environment }
  depends_on = [aws_lb_listener.https, aws_iam_role_policy.execution]
}
