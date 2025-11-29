variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "instance_label" {
  description = "Label for the Linode instance"
  type        = string
  default     = "fameliza"
}

variable "region" {
  description = "Linode region"
  type        = string
  default     = "us-east"
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
  default     = "g6-nanode-1"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "root_password" {
  description = "Root password for the instance (will be changed on first login)"
  type        = string
  sensitive   = true
}

variable "git_repo" {
  description = "Git repository URL"
  type        = string
  default     = ""
}

variable "git_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "domain" {
  description = "Domain name for the application"
  type        = string
  default     = "ai.fame.support"
}

