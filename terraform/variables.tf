variable "project_id" {
    description = "GCP project ID"
    type = string
}

variable "region" {
    description = "Default GCP region"
    type = string
    default = "us-central1"
}

variable "zone" {
    description = "Default GCP zone"
    type = string
    default = "us-central1-a"
}

variable "zomboid_port" {
  description = "UDP port the Zomboid dedicated server listens on"
  type        = number
  default     = 16261
}

variable "rcon_port" {
  description = "TCP port for Zomboid RCON remote administration"
  type        = number
  default     = 27015
}

variable "internal_source_range" {
  description = "CIDR range allowed to reach RCON internally -- matches the Serverless VPC Connector subnet built in Phase 3"
  type        = string
  default     = "10.8.0.0/28"
}