variable "iam_role" {
  type        = string
  default     = "arn:aws:iam::356143132518:role/lambda_iam_role"
  description = "Lambda IAM Role"
}
variable "lambda_name" {
  type        = string
  default     = "CW-Alarm-Creation"
  description = "lamda function name"
}

variable "sns_arn" {
  type        = string
  default     = "arn:aws:sns:us-east-1:356143132518:cloudwatch_alarm"
  description = "description"
}
