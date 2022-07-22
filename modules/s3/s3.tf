#--------------------------------------------------------------
# Estos modulos crea los recursos necesarios el s3
#--------------------------------------------------------------

# Variables Globales
variable "name"                      { default = null }
variable "tags"                      { default = null }
variable "vpc_id"                    { default = null }
variable "create_bucket"             { default = true }
variable "bucket_prefix"             { default = null }
variable "acl"                       { default = "private" }
variable "versioning"                { default = {} }
variable "website"                   { default = {} }
variable "cors_rule"                 { default = [] }
variable "logging"                   { default = {} }
variable "grant"                     { default = [] }
variable "lifecycle_rule"            { default = [] }
variable "replication_configuration" { default = {} }
variable "route_table_ids"           { default = [] }
# Variables Public Access Block
variable "block_public_acls"         { default = false }
variable "block_public_policy"       { default = false }
variable "ignore_public_acls"        { default = false }
variable "restrict_public_buckets"   { default = false }
# Variable Policy
variable "attach_elb_log_delivery_policy" {
  description = "Controls if S3 bucket should have ELB log delivery policy attached"
  type        = bool
  default     = false
}

variable "attach_deny_insecure_transport_policy" {
  description = "Controls if S3 bucket should have deny non-SSL transport policy attached"
  type        = bool
  default     = false
}

variable "attach_policy" {
  description = "Controls if S3 bucket should have bucket policy attached (set to `true` to use value of `policy` as bucket policy)"
  type        = bool
  default     = false 
}

variable "attach_public_policy" {
  description = "Controls if a user defined public bucket policy will be attached (set to `false` to allow upstream to apply defaults to the bucket)"
  type        = bool
  default     = true
}

variable "policy" {
  description = "(Optional) A valid bucket policy JSON document. Note that if the policy document is not specific enough (but still valid), Terraform may view the policy as constantly changing in a terraform plan. In this case, please make sure you use the verbose/specific version of the policy. For more information about building AWS IAM policy documents with Terraform, see the AWS IAM Policy Document Guide."
  type        = string
  default     = null
}

locals {
  attach_policy = var.attach_elb_log_delivery_policy || var.attach_deny_insecure_transport_policy || var.attach_policy
}

resource "aws_s3_bucket" "bucket" {
  count = var.create_bucket ? 1 : 0

  bucket        = var.name
  bucket_prefix = var.bucket_prefix
  acl           = var.acl
  force_destroy = true

  dynamic "versioning" {
    for_each = length(keys(var.versioning)) == 0 ? [] : [var.versioning]

    content {
      enabled    = lookup(versioning.value, "enabled", null)
      mfa_delete = lookup(versioning.value, "mfa_delete", null)
    }
  }

  dynamic "website" {
    for_each = length(keys(var.website)) == 0 ? [] : [var.website]

    content {
      index_document           = lookup(website.value, "index_document", null)
      error_document           = lookup(website.value, "error_document", null)
      redirect_all_requests_to = lookup(website.value, "redirect_all_requests_to", null)
      routing_rules            = lookup(website.value, "routing_rules", null)
    }
  }

  dynamic "cors_rule" {
    for_each = try(jsondecode(var.cors_rule), var.cors_rule)

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }

  dynamic "logging" {
    for_each = length(keys(var.logging)) == 0 ? [] : [var.logging]

    content {
      target_bucket = logging.value.target_bucket
      target_prefix = lookup(logging.value, "target_prefix", null)
    }
  }

  dynamic "grant" {
    for_each = try(jsondecode(var.grant), var.grant)

    content {
      id          = lookup(grant.value, "id", null)
      type        = grant.value.type
      permissions = grant.value.permissions
      uri         = lookup(grant.value, "uri", null)
    }
  }

  dynamic "lifecycle_rule" {
    for_each = try(jsondecode(var.lifecycle_rule), var.lifecycle_rule)

    content {
      id                                     = lookup(lifecycle_rule.value, "id", null)
      prefix                                 = lookup(lifecycle_rule.value, "prefix", null)
      tags                                   = lookup(lifecycle_rule.value, "tags", null)
      abort_incomplete_multipart_upload_days = lookup(lifecycle_rule.value, "abort_incomplete_multipart_upload_days", null)
      enabled                                = lifecycle_rule.value.enabled

      # Max 1 block - expiration
      dynamic "expiration" {
        for_each = length(keys(lookup(lifecycle_rule.value, "expiration", {}))) == 0 ? [] : [lookup(lifecycle_rule.value, "expiration", {})]

        content {
          date                         = lookup(expiration.value, "date", null)
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      # Several blocks - transition
      dynamic "transition" {
        for_each = lookup(lifecycle_rule.value, "transition", [])

        content {
          date          = lookup(transition.value, "date", null)
          days          = lookup(transition.value, "days", null)
          storage_class = transition.value.storage_class
        }
      }

      # Max 1 block - noncurrent_version_expiration
      dynamic "noncurrent_version_expiration" {
        for_each = length(keys(lookup(lifecycle_rule.value, "noncurrent_version_expiration", {}))) == 0 ? [] : [lookup(lifecycle_rule.value, "noncurrent_version_expiration", {})]

        content {
          days = lookup(noncurrent_version_expiration.value, "days", null)
        }
      }

      # Several blocks - noncurrent_version_transition
      dynamic "noncurrent_version_transition" {
        for_each = lookup(lifecycle_rule.value, "noncurrent_version_transition", [])

        content {
          days          = lookup(noncurrent_version_transition.value, "days", null)
          storage_class = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  # Maximo 1 Bloque - replication_configuration
  dynamic "replication_configuration" {
    for_each = length(keys(var.replication_configuration)) == 0 ? [] : [var.replication_configuration]

    content {
      role = replication_configuration.value.role

      dynamic "rules" {
        for_each = replication_configuration.value.rules

        content {
          id       = lookup(rules.value, "id", null)
          priority = lookup(rules.value, "priority", null)
          prefix   = lookup(rules.value, "prefix", null)
          status   = rules.value.status

          dynamic "destination" {
            for_each = length(keys(lookup(rules.value, "destination", {}))) == 0 ? [] : [lookup(rules.value, "destination", {})]

            content {
              bucket             = destination.value.bucket
              storage_class      = lookup(destination.value, "storage_class", null)
              replica_kms_key_id = lookup(destination.value, "replica_kms_key_id", null)
              account_id         = lookup(destination.value, "account_id", null)

              dynamic "access_control_translation" {
                for_each = length(keys(lookup(destination.value, "access_control_translation", {}))) == 0 ? [] : [lookup(destination.value, "access_control_translation", {})]

                content {
                  owner = access_control_translation.value.owner
                }
              }
            }
          }

          dynamic "source_selection_criteria" {
            for_each = length(keys(lookup(rules.value, "source_selection_criteria", {}))) == 0 ? [] : [lookup(rules.value, "source_selection_criteria", {})]

            content {

              dynamic "sse_kms_encrypted_objects" {
                for_each = length(keys(lookup(source_selection_criteria.value, "sse_kms_encrypted_objects", {}))) == 0 ? [] : [lookup(source_selection_criteria.value, "sse_kms_encrypted_objects", {})]

                content {

                  enabled = sse_kms_encrypted_objects.value.enabled
                }
              }
            }
          }

          dynamic "filter" {
            for_each = length(keys(lookup(rules.value, "filter", {}))) == 0 ? [] : [lookup(rules.value, "filter", {})]

            content {
              prefix = lookup(filter.value, "prefix", null)
              tags   = lookup(filter.value, "tags", null)
            }
          }

        }
      }
    }
  }

  tags  = merge(
    var.tags,
    { Name = var.name },
  )
}

resource "aws_s3_bucket_policy" "this" {
  count = var.create_bucket && local.attach_policy ? 1 : 0

  bucket = aws_s3_bucket.bucket[0].id
  policy = data.aws_iam_policy_document.combined[0].json
}

data "aws_iam_policy_document" "combined" {
  count = var.create_bucket && local.attach_policy ? 1 : 0

  source_policy_documents = compact([
    var.attach_elb_log_delivery_policy ? data.aws_iam_policy_document.elb_log_delivery[0].json : "",
    var.attach_deny_insecure_transport_policy ? data.aws_iam_policy_document.deny_insecure_transport[0].json : "",
    var.attach_policy ? var.policy : ""
  ])
}

# AWS Load Balancer access log delivery policy
data "aws_elb_service_account" "this" {
  count = var.create_bucket && var.attach_elb_log_delivery_policy ? 1 : 0
}

data "aws_iam_policy_document" "elb_log_delivery" {
  count = var.create_bucket && var.attach_elb_log_delivery_policy ? 1 : 0

  statement {
    sid = ""

    principals {
      type        = "AWS"
      identifiers = data.aws_elb_service_account.this.*.arn
    }

    effect = "Allow"

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.bucket[0].arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "deny_insecure_transport" {
  count = var.create_bucket && var.attach_deny_insecure_transport_policy ? 1 : 0

  statement {
    sid    = "denyInsecureTransport"
    effect = "Deny"

    actions = [
      "s3:*",
    ]

    resources = [
      aws_s3_bucket.bucket[0].arn,
      "${aws_s3_bucket.bucket[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false"
      ]
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.create_bucket && var.attach_public_policy ? 1 : 0

  # Chain resources (s3_bucket -> s3_bucket_policy -> s3_bucket_public_access_block)
  # to prevent "A conflicting conditional operation is currently in progress against this resource."
  bucket = local.attach_policy ? aws_s3_bucket_policy.this[0].id : aws_s3_bucket.bucket[0].id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

resource "aws_vpc_endpoint" "s3" {
  count        = length(var.route_table_ids) > 0 ? 1 : 0
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.us-east-2.s3"

  tags  = merge(
    var.tags,
    { Name = "${var.name}-s3-endpoint" },
  )
}

resource "aws_vpc_endpoint_route_table_association" "end_s3" {
  count           = length(var.route_table_ids) > 0 ? 1 : 0
  route_table_id  = element(var.route_table_ids, count.index)
  vpc_endpoint_id = element(aws_vpc_endpoint.s3.*.id, 0)

  lifecycle { create_before_destroy = true }
}

output "id" {
  description = "The name of the bucket."
  value       = element(concat(aws_s3_bucket_policy.this.*.id, aws_s3_bucket.bucket.*.id, [""]), 0)
}

output "arn" {
  description = "The ARN of the bucket. Will be of format arn:aws:s3:::bucketname."
  value       = element(concat(aws_s3_bucket.bucket.*.arn, [""]), 0)
}

output "name" { value = var.name }

output "bucket_domain_name" {
  description = "The bucket domain name. Will be of format bucketname.s3.amazonaws.com."
  value       = element(concat(aws_s3_bucket.bucket.*.bucket_domain_name, [""]), 0)
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name. The bucket domain name including the region name, please refer here for format. Note: The AWS CloudFront allows specifying S3 region-specific endpoint when creating S3 origin, it will prevent redirect issues from CloudFront to S3 Origin URL."
  value       = element(concat(aws_s3_bucket.bucket.*.bucket_regional_domain_name, [""]), 0)
}

output "hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = element(concat(aws_s3_bucket.bucket.*.hosted_zone_id, [""]), 0)
}

output "region" {
  description = "The AWS region this bucket resides in."
  value       = element(concat(aws_s3_bucket.bucket.*.region, [""]), 0)
}

output "website_endpoint" {
  description = "The website endpoint, if the bucket is configured with a website. If not, this will be an empty string."
  value       = element(concat(aws_s3_bucket.bucket.*.website_endpoint, [""]), 0)
}

output "website_domain" {
  description = "The domain of the website endpoint, if the bucket is configured with a website. If not, this will be an empty string. This is used to create Route 53 alias records. "
  value       = element(concat(aws_s3_bucket.bucket.*.website_domain, [""]), 0)
}