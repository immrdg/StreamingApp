output "streaming_irsa_role_arn" {
  description = "ARN of IAM role for streaming service IRSA"
  value       = module.streaming_irsa.iam_role_arn
}

output "streaming_irsa_role_name" {
  description = "Name of IAM role for streaming service IRSA"
  value       = module.streaming_irsa.iam_role_name
}
