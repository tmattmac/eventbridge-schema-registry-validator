locals {
  schema_arn_prefix = replace(aws_schemas_registry.schema_registry.arn, "registry/", "schema/")
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_sns_topic" "non_compliant_topic" {
  name = "non-compliant-topic"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.non_compliant_topic.arn
  protocol  = "email"
  endpoint  = "tmcdeane@gmail.com"
}

resource "aws_schemas_registry" "schema_registry" {
  name = "event-schema-registry"
}

resource "aws_iam_role" "eventbridge_lambda_role" {
  name = "eventbridge-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_lambda_role_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.eventbridge_lambda_role.name
}

resource "aws_iam_role_policy" "eventbridge_schema_registry_and_sns_policy" {
  name = "eventbridge-schema-registry-and-sns-policy"
  role = aws_iam_role.eventbridge_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "schemas:ListSchemas",
          "schemas:DescribeSchema"
        ]
        Effect = "Allow"
        Resource = [
          "${local.schema_arn_prefix}/*"
        ]
      },
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = aws_sns_topic.non_compliant_topic.arn
      }
    ]
  })
}

resource "aws_lambda_function" "eventbridge_schema_validator" {
  function_name = "eventbridge-schema-validator"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.eventbridge_lambda_role.arn

  environment {
    variables = {
      SCHEMA_REGISTRY_ARN = aws_schemas_registry.schema_registry.arn
      SNS_TOPIC_ARN       = aws_sns_topic.non_compliant_topic.arn
    }
  }

  # Replace the filename with the path to your lambda deployment package
  filename = "lambda-deployment-package.zip"
}

resource "aws_cloudwatch_event_bus" "event_bus" {
  name = "custom-event-bus"
}

resource "aws_cloudwatch_event_rule" "eventbus_rule" {
  name           = "eventbus-rule"
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  event_pattern = jsonencode({
    "source" : [
      { prefix = "" }
    ]
  })
}

resource "aws_lambda_permission" "eventbridge_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.eventbridge_schema_validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventbus_rule.arn
}

resource "aws_cloudwatch_event_target" "eventbus_lambda_target" {
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  rule           = aws_cloudwatch_event_rule.eventbus_rule.name
  target_id      = "eventbridge-lambda"
  arn            = aws_lambda_function.eventbridge_schema_validator.arn
}

resource "aws_iam_role" "eventbridge_invoke_lambda_role" {
  name = "eventbridge-invoke-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_invoke_lambda_policy" {
  name = "eventbridge-invoke-lambda-policy"
  role = aws_iam_role.eventbridge_invoke_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "lambda:InvokeFunction"
        Effect   = "Allow"
        Resource = aws_lambda_function.eventbridge_schema_validator.arn
      }
    ]
  })
}
