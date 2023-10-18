variable "name" {}
variable "policies" { type = set(string) }
variable "cluster_oidc" {}
variable "namespace" { default = "*" }
variable "service_account" { default = "*" }

variable "app" {}
variable "env" {}

output "arn" {
  value = aws_iam_role.role.arn
}

locals {
  sanitized_name   = replace(replace(lower(replace(replace(var.name, ".modules", "-m-"), ".externals", "-e-")), "/[^a-z\\-0-9]/", "-"), "/-*$/", "") #https://github.com/edgelaboratories/terraform-short-name/blob/main/main.tf
  name_is_too_long = length(local.sanitized_name) > 40
  truncated_name   = replace(substr(local.sanitized_name, 0, 40 - 1 - 0), "/-*$/", "")
  name             = local.name_is_too_long ? local.truncated_name : local.sanitized_name
}

resource "aws_iam_role_policy_attachment" "policies" {
  for_each   = var.policies
  role       = aws_iam_role.role.name
  policy_arn = each.value
}

resource "aws_iam_role" "role" {
  name_prefix = local.name
  // below uses StringLike to allow wildcards for multiple service accounts within the same namespace for workloads
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.cluster_oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : {
            "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.cluster_oidc}:sub" : "system:serviceaccount:${var.namespace}:${var.service_account}",
            "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.cluster_oidc}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
    }
  )

  tags = {
    env = "${var.app}-${var.env}"
  }

}

// boilerplate for Humanitec terraform driver
variable "region" {}
variable "access_key" {}
variable "secret_key" {}
variable "assume_role_arn" { default = "" }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
  dynamic "assume_role" {
    for_each = (var.assume_role_arn == "") == true ? [] : [1]
    content {
      role_arn = var.assume_role_arn
    }
  }

}
