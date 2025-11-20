terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# IoT Core Topic Rule
resource "aws_iot_topic_rule" "iot_to_firehose" {
  name        = "iot_to_firehose_rule"
  description = "Route IoT data to Kinesis Firehose"
  enabled     = true
  sql         = "SELECT * FROM 'iot/data'"
  sql_version = "2016-03-23"

  # Firehose action configuration
  firehose {
    delivery_stream_name = aws_kinesis_firehose_delivery_stream.iot_firehose.name
    role_arn             = aws_iam_role.iot_firehose_role.arn
    separator            = "\n" # Newline separator between records
  }
}

# Kinesis Firehose Delivery Stream
resource "aws_kinesis_firehose_delivery_stream" "iot_firehose" {
  name        = "iot-firehose-stream"
  destination = "extended_s3"

  # Extended S3 destination configuration
  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_s3_role.arn
    bucket_arn = aws_s3_bucket.iot_data.arn

    buffering_interval = 20
    
    # Hive-style partitioning
    prefix = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"
    
  }
}

# S3 Bucket for IoT Data
resource "aws_s3_bucket" "iot_data" {
  bucket = "${var.s3_bucket_name}-${random_id.suffix.hex}"
  force_destroy = true
}

# IAM Role for IoT Core to write to Firehose
resource "aws_iam_role" "iot_firehose_role" {
  name = "iot-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Role for Firehose to write to S3
resource "aws_iam_role" "firehose_s3_role" {
  name = "firehose-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for IoT Core to write to Firehose
resource "aws_iam_role_policy" "iot_firehose_policy" {
  name = "iot-firehose-policy"
  role = aws_iam_role.iot_firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.iot_firehose.arn
      }
    ]
  })
}

# IAM Policy for Firehose to write to S3
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "firehose-s3-policy"
  role = aws_iam_role.firehose_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.iot_data.arn,
          "${aws_s3_bucket.iot_data.arn}/*"
        ]
      }
    ]
  })
}

/* helper for a unique bucket name */
resource "random_id" "suffix" {
  byte_length = 4
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "iot-sim-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attach the AWS‑managed basic execution policy (logs to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach the AWS‑managed iot core data access policy to lambda
resource "aws_iam_role_policy_attachment" "iot_data_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSIoTDataAccess"
}

# Build a zip archive for the code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../iot_simulator"
  output_path = "${path.module}/../iot_simulator.zip"
}

# Lambda function resource
resource "aws_lambda_function" "iot_sim" {
  function_name = "iot_simulator"
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  role          = aws_iam_role.lambda_exec.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Optional but recommended for production stability
  timeout = 30          # seconds
  memory_size = 128     # MB
}

# EventBridge schedule rule
resource "aws_cloudwatch_event_rule" "every-minute-schedule" {
  name                = "one-minute-trigger"
  description         = "Invokes the Lambda every ten seconds"
  schedule_expression = "rate(1 minute)"
}

# Target – the Lambda func
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every-minute-schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.iot_sim.arn
}

# Permission so EventBridge can call the Lambda
resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iot_sim.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every-minute-schedule.arn
}

# IAM role for SageMaker notebook instance
resource "aws_iam_role" "sagemaker_notebook_role" {
  name = "sagemaker-notebook-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the AmazonSageMakerFullAccess policy to the role
resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_notebook_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Create the SageMaker notebook instance
resource "aws_sagemaker_notebook_instance" "notebook" {
  name                  = "failure-risk-notebook-instance"
  role_arn              = aws_iam_role.sagemaker_notebook_role.arn
  instance_type         = "ml.t3.medium"
  platform_identifier   = "notebook-al2-v3"
  
  # Configure volume size (default is 5GB)
  volume_size = 20
  
  # Enable direct internet access (default is Enabled)
  direct_internet_access = "Enabled"
  
  # Configure root access (default is Enabled)
  root_access = "Enabled"
  
  tags = {
    Name = "FailureRiskNotebookInstance"
  }
}
