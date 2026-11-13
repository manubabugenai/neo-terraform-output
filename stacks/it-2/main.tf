terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5"
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

# Define labels once in a locals block
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Requirement: 1 Pub/Sub topic for application events
resource "google_pubsub_topic" "it2_app_notifications_topic" {
  project = var.project_id
  # Naming: quantum-<env>-<service>
  name    = "quantum-${var.environment}-it2-app-notifications"
  # Requirement: Message retention: 7 days (604800 seconds)
  message_retention_duration = "604800s"
  # Labels: Apply to every resource that supports a labels argument
  labels = local.labels
}

# Requirement: 1 subscription (pull)
resource "google_pubsub_subscription" "it2_app_notifications_sub" {
  project = var.project_id
  # Naming: quantum-<env>-<service> (using topic name + -sub)
  name    = "quantum-${var.environment}-it2-app-notifications-sub"
  topic   = google_pubsub_topic.it2_app_notifications_topic.id
  # Requirement: pull delivery type
  ack_deadline_seconds = 10
  # Requirement: Message retention: 7 days (604800 seconds)
  message_retention_duration = "604800s"
  # Labels: Apply to every resource that supports a labels argument
  labels = local.labels
}
