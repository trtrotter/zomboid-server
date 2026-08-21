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

variable "instance_name" {
  description = "Name of the Zomboid game server VM"
  type        = string
  default     = "zomboid-server"
}

variable "machine_type" {
  description = "GCE machine type for the game server"
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 10
}

variable "data_disk_size_gb" {
  description = "Size of the persistent data disk holding world saves, in GB"
  type        = number
  default     = 10
}

variable "server_name" {
  description = "Project Zomboid server name (used in save path and PZ client server list)"
  type        = string
  default     = "trottcg-zomboid"
}

variable "discord_public_key" {
  description = "Discord application's public key, used to verify interaction request signatures"
  type        = string
}

variable "discord_application_id" {
  description = "Discord application ID"
  type        = string
}