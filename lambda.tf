resource "aws_lambda_function" "CW-Alarm-Creation" {
  description = "Lambda function to create cloudwatch alarms"
  filename      = "files/lambda_function.zip"
  function_name = var.lambda_name
  role          = var.iam_role
  handler       = "lambda_function.lambda_handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("files/lambda_function.zip")

  runtime = "python3.8"
  memory_size =  "128"
  timeout = "300"

  environment {
    variables = {
      sns_arn = var.sns_arn
    }
  }
}

