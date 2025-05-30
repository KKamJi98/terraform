###############################################################
data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  oidc_issuer = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}
# Policy
###############################################################

data "aws_iam_policy_document" "external_secrets" {
  # SSM Parameter Store 접근 정책
  statement {
    sid = "SSMParameterStoreAccess"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:DescribeParameters"
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${local.account_id}:parameter/*"
    ]
  }

  # Secrets Manager 접근 정책
  statement {
    sid = "SecretsManagerReadAccess"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:*"
    ]
  }

  statement {
    sid = "SecretsManagerListAndPolicy"
    actions = [
      "secretsmanager:ListSecrets"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values = [
        "system:serviceaccount:external-secrets:external-secrets-irsa"
      ]
    }
    effect = "Allow"
  }
}

###############################################################
# IAM Role
###############################################################
resource "aws_iam_role" "external_secrets" {
  name               = "kkamji_external_secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

###############################################################
# Managed Policy
###############################################################
resource "aws_iam_policy" "external_secrets_policy" {
  name        = "kkamji_external_secrets_policy"
  description = "Policy for External Secrets to access SSM Parameter Store and Secrets Manager"
  policy      = data.aws_iam_policy_document.external_secrets.json
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

###############################################################
# IAM Role Policy Attachment
###############################################################
resource "aws_iam_role_policy_attachment" "external_secrets_policy_attachment" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets_policy.arn
}

#############################
# Kubernetes Namespace 생성 (IRSA)
#############################

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

#############################
# Kubernetes ServiceAccount 생성 (IRSA)
#############################

resource "kubernetes_service_account" "external_secrets_irsa" {
  metadata {
    name      = "external-secrets-irsa"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
    annotations = {
      # IRSA IAM 역할의 ARN을 동적으로 참조합니다.
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }
}