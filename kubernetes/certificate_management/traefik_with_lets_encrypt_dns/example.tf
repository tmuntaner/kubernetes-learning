variable "route_53_hosted_zone" {}
variable "eks_federated_web_identity" {}
variable "cert_manager_namespace" {
  default = "cert-manager"
}
variable "cert_manager_service_account" {
  default = "cert-manager"
}

resource "aws_iam_policy" "cert_manager" {
  name        = "cert-manager"
  path        = "/"
  description = "dns permissions for cert_manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "route53:GetChange"
        ],
        Resource = [
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ],
        Resource = [
          "arn:aws:route53:::hostedzone/${var.route_53_hosted_zone}"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "route53:ListHostedZonesByName",
        ],
        Resource = [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "cert_manager" {
  name = "cert-manager"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = var.eks_federated_web_identity
        }
        Condition = {
          StringEquals = {
            "oidc.eks.eu-west-1.amazonaws.com/id/E74856BD818DB239C07AA1D72F74E83B:sub" = "system:serviceaccount:${var.cert_manager_namespace}:${var.cert_manager_service_account}"
            "oidc.eks.eu-west-1.amazonaws.com/id/E74856BD818DB239C07AA1D72F74E83B:aud" = "sts.amazonaws.com"
          }
        }
      }
    ],
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  policy_arn = aws_iam_policy.cert_manager.arn
  role = aws_iam_role.cert_manager.name
}

output "iam_role_arn" {
  value = aws_iam_role.cert_manager.arn
}
