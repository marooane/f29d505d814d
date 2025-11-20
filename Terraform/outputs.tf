# IoT Core Topic Rule ARN
output "iot_topic_rule_arn" {
  description = "ARN of the IoT Core Topic Rule"
  value       = aws_iot_topic_rule.iot_to_firehose.arn
}

# Kinesis Firehose Delivery Stream ARN
output "firehose_stream_arn" {
  description = "ARN of the Kinesis Firehose Delivery Stream"
  value       = aws_kinesis_firehose_delivery_stream.iot_firehose.arn
}

# S3 Bucket Name
output "s3_bucket_name" {
  description = "Name of the S3 bucket for IoT data"
  value       = aws_s3_bucket.iot_data.bucket
}

# S3 Bucket ARN
output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for IoT data"
  value       = aws_s3_bucket.iot_data.arn
}

# IoT Data Ingestion URL (for device connectivity)
output "iot_data_endpoint" {
  description = "IoT Core endpoint for device connectivity"
  value       = "${aws_iot_topic_rule.iot_to_firehose.name}/iot/data"
}

# The notebook instance ARN
output "notebook_instance_arn" {
  value = aws_sagemaker_notebook_instance.notebook.arn
}

# The notebook instance URL
output "notebook_instance_url" {
  value = aws_sagemaker_notebook_instance.notebook.url
}