# AWS region
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# S3 bucket name for IoT data storage
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storing IoT data"
  type        = string
}

# IoT topic for data ingestion (optional)
variable "iot_topic" {
  description = "IoT topic to subscribe to for data ingestion"
  type        = string
  default     = "iot/data"
}