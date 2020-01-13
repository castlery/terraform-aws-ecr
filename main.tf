locals {
  principals_readonly_access_non_empty = length(var.principals_readonly_access) > 0 ? true : false
  principals_full_access_non_empty     = length(var.principals_full_access) > 0 ? true : false
  ecr_need_policy                      = length(var.principals_full_access) + length(var.principals_readonly_access) > 0 ? true : false
}

module "label" {
  source              = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled             = var.enabled
  namespace           = var.namespace
  stage               = var.stage
  name                = var.name
  delimiter           = var.delimiter
  attributes          = var.attributes
  tags                = var.tags
  regex_replace_chars = var.regex_replace_chars
}

resource "aws_ecr_repository" "default" {
  count = var.enabled ? 1 : 0
  name  = var.use_fullname ? module.label.id : module.label.name

  image_scanning_configuration {
    scan_on_push = var.scan_images_on_push
  }

  tags = module.label.tags
}

data "template_file" "ecr_lifecycle_policy_rule_tagged" {
  template = "${file("${path.module}/files/rule_tagged.json.tpl")}"
  count    = "${length(var.tag_prefix_list)}"

  vars = {
    priority         = "${count.index + 2}"
    image_limit      = "${var.max_tagged_image_count}"
    image_tag_prefix = "${element(var.tag_prefix_list, count.index)}"
  }
}


resource "aws_ecr_lifecycle_policy" "default" {
  count      = var.enabled ? 1 : 0
  repository = join("", aws_ecr_repository.default.*.name)

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Remove untagged images",
      "selection": {
        "tagStatus": "untagged",
        "countType": "imageCountMoreThan",
        "countNumber": "${var.max_untagged_image_count}"
      },
      "action": {
        "type": "expire"
      }
    },
    ${join(",", data.template_file.ecr_lifecycle_policy_rule_tagged.*.rendered)}
  ]
}
EOF
}

data "aws_iam_policy_document" "empty" {
  count = var.enabled ? 1 : 0
}

data "aws_iam_policy_document" "resource_readonly_access" {
  count = var.enabled ? 1 : 0

  statement {
    sid    = "ReadonlyAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_readonly_access
    }

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:DescribeImageScanFindings",
    ]
  }
}

data "aws_iam_policy_document" "resource_full_access" {
  count = var.enabled ? 1 : 0

  statement {
    sid    = "FullAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_full_access
    }

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:DescribeImageScanFindings",
      "ecr:StartImageScan",
    ]
  }
}

data "aws_iam_policy_document" "resource" {
  count         = var.enabled ? 1 : 0
  source_json   = local.principals_readonly_access_non_empty ? join("", data.aws_iam_policy_document.resource_readonly_access.*.json) : join("", data.aws_iam_policy_document.empty.*.json)
  override_json = local.principals_full_access_non_empty ? join("", data.aws_iam_policy_document.resource_full_access.*.json) : join("", data.aws_iam_policy_document.empty.*.json)
}

resource "aws_ecr_repository_policy" "default" {
  count      = local.ecr_need_policy && var.enabled ? 1 : 0
  repository = join("", aws_ecr_repository.default.*.name)
  policy     = join("", data.aws_iam_policy_document.resource.*.json)
}
