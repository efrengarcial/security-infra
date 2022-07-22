provider "aws" {
    region="us-east-1"
    profile = "default"
}

variable "stack_id"                  { }
variable "layer"                     { }
variable "name"                      { }
variable "tags"                      { }


module "bucket_lambda" {
  source = "../../modules/s3"
  name   = "${var.name}-lambda"
  acl    = "private"
}

module "postConfirmation" {
  source        = "../../modules/compute/lambda"
  name = var.name
  tags = var.tags
  function_name = "postConfirmation"
  s3_bucket     = module.bucket_lambda.name
  s3_key        = "postConfirmation.zip"
  handler       = "bin/postConfirmation"
  runtime       = "go1.x"

  depends_on = [
    module.bucket_lambda,
  ]
}
