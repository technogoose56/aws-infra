variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "max_image_count" {
  description = "Maximum number of untagged images to retain"
  type        = number
  default     = 5
}
