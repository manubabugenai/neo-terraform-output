# main.tf for stack it-2

# Terraform and Provider configuration
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Declare exactly these variables as per Quantum Terraform Standards
variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region for resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources."
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"
}

# Define labels once in a locals block and reference local.labels
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Infrastructure Requirements

# Requirement: 1 Pub/Sub topic for application notifications
resource "google_pubsub_topic" "it2_app_notifications_topic" {
  project = var.project_id
  # Naming: quantum-<env>-<service>
  name    = "quantum-${var.environment}-it2-app-notifications"
  labels  = local.labels

  # Requirement: Message retention: 7 days
  # 7 days = 7 * 24 * 60 * 60 seconds = 604800 seconds
  message_retention_duration = "604800s"
}

# Requirement: 1 subscription (pull) for the Pub/Sub topic
resource "google_pubsub_subscription" "it2_app_notifications_sub" {
  project = var.project_id
  # Naming: quantum-<env>-<service>
  name    = "quantum-${var.environment}-it2-app-notifications-sub"
  topic   = google_pubsub_topic.it2_app_notifications_topic.id
  labels  = local.labels

  # Default delivery type is PULL, no explicit configuration needed for this.
  # ack_deadline_seconds and expiration_policy can be configured if needed,
  # but not specified in requirements.
}
