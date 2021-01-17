terraform {
  experiments = [variable_validation]
}

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
  default     = "amazon/aws-for-fluent-bit:2.10.0"
  description = "The Docker image to run"

  validation {
    condition     = can(regex("^amazon/aws-for-fluent-bit:", var.image))
    error_message = "You must use a amazon/aws-for-fluent-bit image and include the version."
  }
}
