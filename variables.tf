variable "namespace" {
  default     = "aws"
  description = "The k8s namespace to install the agent in"
}

variable "cluster_id" {
  description = "The EKS cluster_id"
}

variable "region" {
  description = "The region to run in"
}

variable "image" {
  default     = "amazon/aws-for-fluent-bit:2.10.1"
  description = "The Docker image to run"

  validation {
    condition     = can(regex("^amazon/aws-for-fluent-bit:", var.image))
    error_message = "You must use a amazon/aws-for-fluent-bit image and include the version."
  }
}

variable "cluster_oidc_issuer_url" {
  description = "The cluster_oidc_issuer_url for the EKS cluster"
}

variable "oidc_provider_arn" {
  description = "The oidc_provider_arn for the EKS cluster"
}

variable "log_level" {
  default     = "warn"
  description = "Log level for fluent-bit"

  validation {
    condition     = contains(["error", "warn", "info", "debug"], var.log_level)
    error_message = "Must be one of error, warn, info, debug."
  }
}

variable "http_server" {
  default     = true
  description = "Whether to run the HTTP server for metrics and stuff"
}

variable "http_server_port" {
  default     = 2020
  description = "HTTP server port"
}
