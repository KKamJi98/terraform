######################################################################
## Base Terraform variables
######################################################################
variable "region" {
  description = "The AWS region to create resources in"
  type        = string
  default     = "ap-northeast-2"
}