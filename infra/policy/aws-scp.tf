# AWS guardrails — Service Control Policies attached to the workloads OU (doc 04 §2).
# Preventive: deny public exposure and out-of-region resources org-wide.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "workloads_ou_id" {
  description = "OU containing all workload + network accounts."
  type        = string
}

resource "aws_organizations_policy" "no_public_exposure" {
  name        = "deny-public-exposure"
  description = "No IGW, public IPs, EIPs, or internet-facing LBs; region lock."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInternetGateways"
        Effect = "Deny"
        Action = [
          "ec2:CreateInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:CreateEgressOnlyInternetGateway"
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyPublicIPOnLaunch"
        Effect   = "Deny"
        Action   = "ec2:RunInstances"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = { Bool = { "ec2:AssociatePublicIpAddress" = "true" } }
      },
      {
        Sid      = "DenyElasticIPs"
        Effect   = "Deny"
        Action   = ["ec2:AllocateAddress", "ec2:AssociateAddress"]
        Resource = "*"
      },
      {
        Sid      = "DenyPublicLoadBalancers"
        Effect   = "Deny"
        Action   = "elasticloadbalancing:CreateLoadBalancer"
        Resource = "*"
        Condition = { StringEquals = { "elasticloadbalancing:Scheme" = "internet-facing" } }
      },
      {
        Sid       = "RestrictRegions"
        Effect    = "Deny"
        NotAction = ["iam:*", "organizations:*", "route53:*", "cloudfront:*", "sts:*"]
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:RequestedRegion" = ["eu-west-1"] } }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "no_public_exposure" {
  policy_id = aws_organizations_policy.no_public_exposure.id
  target_id = var.workloads_ou_id
}
