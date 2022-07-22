variable "name"                 { default = "lambda" }
variable "tags"                 {}
variable "s3_bucket"            { default = null}
variable "s3_key"               { default = null}
variable "function_name"        {}
variable "runtime"              { default = "nodejs14.x" }
variable "handler"              { default = "main.handler" }
variable "custom_policy"        { default = [] }
variable "environment"          { default = {} }    
variable "subnets"              { default = [] }
variable "sg_ids"               { default = [] }
variable "publish"              { default = false }

# IAM role which dictates what other AWS services the Lambda function
resource "aws_iam_role" "lambda_exec" {
   name = "role-${var.name}-${var.function_name}"
   assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "policy-${var.name}-${var.function_name}-lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_policy" "custom_policy" {
  count = length(var.custom_policy) > 0 ? length(var.custom_policy) : 0

  name = "role-${var.name}-${var.function_name}-${lookup(element(var.custom_policy, count.index), "name")}"

  policy = jsonencode(lookup(element(var.custom_policy, count.index), "policy"))
}

resource "aws_iam_role_policy_attachment" "custom_attchment" {
  count = length(var.custom_policy) > 0 ? length(var.custom_policy) : 0

  role       = aws_iam_role.lambda_exec.name
  policy_arn = element(aws_iam_policy.custom_policy.*.arn, count.index)
}

data "aws_s3_bucket_object" "bucket_object_lambda_function_hash" {
  bucket =  var.s3_bucket
  key    = "${var.s3_key}.base64sha256"
}

resource "aws_lambda_function" "main" {
  s3_bucket        = var.s3_bucket
  s3_key           = var.s3_key
  function_name    = var.function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = var.handler
  runtime          = var.runtime
  publish          = var.publish
  source_code_hash = data.aws_s3_bucket_object.bucket_object_lambda_function_hash.body

  dynamic "environment" {
    for_each = length(keys(var.environment)) == 0 ? [] : [var.environment]

    content {
      variables = environment.value  //lookup(environment.value, "variables", null)
    }
  }

  vpc_config {
    subnet_ids         = var.subnets
    security_group_ids = var.sg_ids
  }

  tags  = merge(
    var.tags,
    { Name = "${var.name}" },
  )

  depends_on = [
    aws_cloudwatch_log_group.main,
  ]

  lifecycle {
    ignore_changes = [
      source_code_hash,
      last_modified,
      qualified_arn,
      version
    ]
  }

}

// CloudWatch logs to stream all module
resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7

  tags  = merge(
    var.tags,
    { Name = "${var.name}" },
  )
}

output "arn" { value = "${aws_lambda_function.main.arn}" }
output "invoke_arn" { value = "${aws_lambda_function.main.invoke_arn}" }
output "qualified_arn" { value = "${aws_lambda_function.main.qualified_arn}" }
