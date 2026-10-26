terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3         = "http://localhost:4566"
    sqs        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    iam        = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
    logs       = "http://localhost:4566"
  }
}

# --- 1. SQS QUEUES (Principal & DLQ) ---

resource "aws_sqs_queue" "dlq" {
  name                      = "sre-dead-letter-queue"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "main_queue" {
  name                       = "sre-processing-queue"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 2
  })
}

resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.main_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "SQS:SendMessage"
        Resource  = aws_sqs_queue.main_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.ingestion_bucket.arn
          }
        }
      }
    ]
  })
}

# --- 2. S3 BUCKET & NOTIFICATION ---

resource "aws_s3_bucket" "ingestion_bucket" {
  bucket = "sre-ingestion-bucket"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.ingestion_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.main_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".json"
  }

  depends_on = [aws_sqs_queue_policy.sqs_policy]
}

# --- 3. IAM ROLE PARA LAMBDA ---

resource "aws_iam_role" "lambda_role" {
  name = "sre_lambda_execution_role"

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

# --- 4. LAMBDA FUNCTION ---

resource "aws_lambda_function" "processor" {
  filename         = "lambda.zip"
  function_name    = "sre-processor-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      ENV = "local"
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main_queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 1
  enabled          = true
}

# --- OUTPUTS ---

output "s3_bucket_name" {
  value = aws_s3_bucket.ingestion_bucket.id
}

output "sqs_main_url" {
  value = aws_sqs_queue.main_queue.id
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.dlq.id
}
